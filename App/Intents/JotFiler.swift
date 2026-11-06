import Foundation

/// Jot without the sheet: what Siri and Shortcuts call. Reads the line the same
/// way the Jot sheet does (rules first, the on-device model when there is one)
/// and files it, then says what it did in one sentence.
@MainActor
enum JotFiler {
    struct Filed: Equatable {
        enum Item: Equatable {
            case reminder(String, due: Date?)
            case note(String)
            case personNote(String, name: String)
        }
        var items: [Item]
        var summary: String
    }

    enum JotError: LocalizedError {
        case empty, noReminders
        var errorDescription: String? {
            switch self {
            case .empty: "There was nothing to jot."
            case .noReminders: "Shebang#! needs Reminders for to-dos. Open the app, jot a to-do once, and allow Reminders."
            }
        }
    }

    /// What the line becomes, without saving anything.
    static func plan(_ raw: String, contacts: [ContactSnapshot], now: Date = .now) async -> [Filed.Item] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let pieces = OnDevice.isAvailable ? (await ModelCapture.todos(in: text) ?? RuleCapture.split(text)) : RuleCapture.split(text)
        if pieces.count >= 2 {
            var out: [Filed.Item] = []
            for p in pieces.prefix(12) {
                var g = RuleCapture.todo(p)
                if g.due == nil, Horizon.stated(in: p.lowercased()) == nil, let h = await ModelCapture.horizon(for: p, now: now) { g.horizon = h }
                out.append(.reminder(g.text, due: g.due ?? g.horizon.date(from: now)))
            }
            return out
        }
        let g = await CaptureReader.read(text, now: now)
        switch g.kind {
        case .reminder:
            return [.reminder(g.text.isEmpty ? text : g.text, due: g.due ?? g.horizon.date(from: now))]
        case .person:
            if let name = g.person, let c = ContactMatcher.sure(ContactMatcher.matches(for: name, in: contacts)) {
                return [.personNote(g.text.isEmpty ? text : g.text, name: c.person.fullName)]
            }
            return [.note(text)]
        case .note, .occasion:
            return [.note(text)]
        }
    }

    /// Plans and saves. To-dos go to Reminders, the rest to Shebang#!.
    static func file(_ raw: String, now: Date = .now) async throws -> Filed {
        let model = AppModel.shared
        if model.contactChoices.isEmpty, model.contactsAccess.canRead { await model.reload() }
        let contacts = model.contactChoices
        let items = await plan(raw, contacts: contacts, now: now)
        guard !items.isEmpty else { throw JotError.empty }

        let reminders: [(String, Date?)] = items.compactMap { item in
            guard case let .reminder(t, d) = item else { return nil }
            return (t, d)
        }
        if !reminders.isEmpty {
            guard await RemindersService.shared.requestReminderAccess() else { throw JotError.noReminders }
            for (t, d) in reminders { try await RemindersService.shared.add(t, due: d, hasTime: false) }
        }
        for item in items {
            switch item {
            case .note(let t): HubStore.shared.addNote(body: t)
            case .personNote(let t, let name):
                if let id = ContactMatcher.sure(ContactMatcher.matches(for: name, in: contacts))?.id {
                    HubStore.shared.addPersonNote(t, contactID: id)
                } else {
                    HubStore.shared.addNote(body: t)
                }
            case .reminder: break
            }
        }
        return Filed(items: items, summary: summary(items, now: now))
    }

    static func summary(_ items: [Filed.Item], now: Date = .now) -> String {
        if items.count > 1 {
            let names: [String] = items.compactMap { item in
                guard case let .reminder(t, _) = item else { return nil }
                return "\u{201C}\(t)\u{201D}"
            }
            return "Added \(items.count) to-dos to Reminders: \(ListFormatter.localizedString(byJoining: names))."
        }
        switch items.first {
        case .reminder(let t, let due)?:
            guard let due else { return "Added \u{201C}\(t)\u{201D} to Reminders." }
            return "Added \u{201C}\(t)\u{201D} to Reminders, due \(due.friendly(withTime: false, now: now))."
        case .personNote(_, let name)?:
            return "Saved that about \(name)."
        case .note?:
            return "Saved it as a note."
        case nil:
            return "Nothing to jot."
        }
    }
}
