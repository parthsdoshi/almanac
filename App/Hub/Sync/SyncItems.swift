import Foundation

// What iCloud sync moves, as plain data, so it can be tested without CloudKit.
// Each thing is one record named by kind and id; its payload is JSON.

enum SyncKind: String, Sendable {
    case note, personNote, session, bodyweight, prefs
}

/// The settings, stars and mutes, in a form another phone can read: stars and mutes are keyed by
/// the people's names, because contact ids (and the occasion ids built from them) differ per phone.
struct SyncPrefs: Codable, Equatable, Sendable {
    var settings = Settings()
    var weights: [String: Double] = [:]
    var overrides: [String: String] = [:]
    var starred: [String] = []
    var muted: [String: String] = [:]
}

/// What a payload carries: when it last changed, and the thing itself.
struct SyncEnvelope: Codable, Sendable {
    var modified: Date
    var data: Data
}

/// How this phone's occasions and contacts line up with the names another phone uses.
struct SyncKeys: Sendable {
    /// occasion id -> "birthday|priya patel"
    var portable: [String: String] = [:]
    /// "birthday|priya patel" -> occasion id
    var local: [String: String] = [:]
    /// contact id -> normalized full name
    var contactName: [String: String] = [:]
    /// normalized full name -> contact id, only for names one contact has
    var contactByName: [String: String] = [:]

    static func build(occasions: [Occasion], contacts: [ContactSnapshot]) -> SyncKeys {
        var k = SyncKeys()
        for o in occasions {
            let key = portableKey(kind: o.kind.rawValue, names: o.people.map(\.fullName))
            k.portable[o.id] = key
            if k.local[key] == nil { k.local[key] = o.id }
        }
        var counts: [String: Int] = [:]
        for c in contacts {
            let name = normalize([c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " "))
            guard !name.isEmpty else { continue }
            k.contactName[c.id] = name
            counts[name, default: 0] += 1
            k.contactByName[name] = c.id
        }
        for (name, n) in counts where n > 1 { k.contactByName[name] = nil }
        return k
    }

    static func portableKey(kind: String, names: [String]) -> String {
        kind + "|" + names.map(normalize).sorted().joined(separator: "+")
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Stars and mutes from another phone that don't match anyone here (yet), kept so they aren't lost.
struct SyncUnresolved: Codable, Equatable, Sendable {
    var starred: Set<String> = []
    var muted: [String: String] = [:]
}

struct SyncItem: Equatable, Sendable {
    var kind: SyncKind
    var data: Data
    /// When it changed, if the thing itself says (a note's edit time, a workout's date).
    var intrinsic: Date
}

enum SyncItems {
    static let prefsName = "prefs"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func encode<T: Encodable>(_ v: T) -> Data { (try? encoder.encode(v)) ?? Data() }
    static func decode<T: Decodable>(_ t: T.Type, _ d: Data) -> T? { try? decoder.decode(t, from: d) }

    /// Everything that syncs, by record name.
    static func items(hub: HubState, app: PersistedState, keys: SyncKeys, unresolved: SyncUnresolved) -> [String: SyncItem] {
        var out: [String: SyncItem] = [:]
        for n in hub.notes {
            out["note.\(n.id.uuidString)"] = SyncItem(kind: .note, data: encode(n), intrinsic: n.updated)
        }
        for var p in hub.personNotes {
            if let name = keys.contactName[p.contactID] { p.personName = name }
            out["pnote.\(p.id.uuidString)"] = SyncItem(kind: .personNote, data: encode(p), intrinsic: p.created)
        }
        for s in hub.workouts.history {
            out["session.\(s.date)"] = SyncItem(kind: .session, data: encode(s), intrinsic: s.startDate)
        }
        for b in hub.workouts.bodyweight {
            out["bw.\(b.date)"] = SyncItem(kind: .bodyweight, data: encode(b), intrinsic: .distantPast)
        }
        out[prefsName] = SyncItem(kind: .prefs, data: encode(prefs(hub: hub, app: app, keys: keys, unresolved: unresolved)),
                                  intrinsic: Date(timeIntervalSince1970: 0))
        return out
    }

    static func prefs(hub: HubState, app: PersistedState, keys: SyncKeys, unresolved: SyncUnresolved) -> SyncPrefs {
        var p = SyncPrefs()
        p.settings = app.settings
        p.weights = hub.workouts.weights
        p.overrides = hub.workouts.overrides
        p.starred = Array(Set(app.starred.compactMap { keys.portable[$0] }).union(unresolved.starred)).sorted()
        var muted = unresolved.muted
        for (id, title) in app.muted { if let k = keys.portable[id] { muted[k] = title } }
        p.muted = muted
        return p
    }

    /// Puts something from iCloud into this phone's data.
    static func apply(_ kind: SyncKind, _ data: Data, hub: inout HubState, app: inout PersistedState,
                      keys: SyncKeys, unresolved: inout SyncUnresolved) {
        switch kind {
        case .note:
            guard let n = decode(Note.self, data) else { return }
            if let i = hub.notes.firstIndex(where: { $0.id == n.id }) { hub.notes[i] = n } else { hub.notes.append(n) }
            hub.notes.sort { $0.updated > $1.updated }
        case .personNote:
            guard var p = decode(PersonNote.self, data) else { return }
            if keys.contactName[p.contactID] == nil, let name = p.personName, let id = keys.contactByName[name] {
                p.contactID = id
            }
            if let i = hub.personNotes.firstIndex(where: { $0.id == p.id }) { hub.personNotes[i] = p } else { hub.personNotes.append(p) }
        case .session:
            guard let s = decode(WorkoutSession.self, data) else { return }
            if let i = hub.workouts.history.firstIndex(where: { $0.date == s.date }) { hub.workouts.history[i] = s } else {
                hub.workouts.history.append(s)
                hub.workouts.history.sort { $0.startDate < $1.startDate }
            }
        case .bodyweight:
            guard let b = decode(BodyweightEntry.self, data) else { return }
            hub.workouts.bodyweight.removeAll { $0.date == b.date }
            hub.workouts.bodyweight.append(b)
            hub.workouts.bodyweight.sort { $0.date < $1.date }
        case .prefs:
            guard let p = decode(SyncPrefs.self, data) else { return }
            app.settings = p.settings
            hub.workouts.weights = p.weights
            hub.workouts.overrides = p.overrides
            // Stars and mutes this phone can't express by name stay as they are.
            let keepStarred = app.starred.filter { keys.portable[$0] == nil }
            let keepMuted = app.muted.filter { keys.portable[$0.key] == nil }
            var starred = keepStarred
            var muted = keepMuted
            unresolved = SyncUnresolved()
            for k in p.starred {
                if let id = keys.local[k] { starred.insert(id) } else { unresolved.starred.insert(k) }
            }
            for (k, title) in p.muted {
                if let id = keys.local[k] { muted[id] = title } else { unresolved.muted[k] = title }
            }
            app.starred = starred
            app.muted = muted
        }
    }

    /// Something was deleted on another device.
    static func remove(_ name: String, hub: inout HubState) {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "note": hub.notes.removeAll { $0.id.uuidString == parts[1] }
        case "pnote": hub.personNotes.removeAll { $0.id.uuidString == parts[1] }
        case "session": hub.workouts.history.removeAll { $0.date == parts[1] }
        case "bw": hub.workouts.bodyweight.removeAll { $0.date == parts[1] }
        default: break
        }
    }

    /// Once contacts load: stars, mutes and people notes from another phone that now match someone here.
    static func resolve(hub: inout HubState, app: inout PersistedState, keys: SyncKeys, unresolved: inout SyncUnresolved) {
        for k in unresolved.starred {
            if let id = keys.local[k] { app.starred.insert(id); unresolved.starred.remove(k) }
        }
        for (k, title) in unresolved.muted {
            if let id = keys.local[k] { app.muted[id] = title; unresolved.muted[k] = nil }
        }
        for i in hub.personNotes.indices where keys.contactName[hub.personNotes[i].contactID] == nil {
            if let name = hub.personNotes[i].personName, let id = keys.contactByName[name] { hub.personNotes[i].contactID = id }
        }
    }
}
