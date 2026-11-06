import CloudKit
import Foundation
import Observation

/// Keeps notes, people notes, workouts, settings, stars and mutes in step across your devices,
/// in your own iCloud (the private database). One record per thing; the newer edit wins.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()
    static let enabledKey = "icloud.sync"
    static let recordType = "Item"

    /// For Settings.
    private(set) var lastSynced: Date?
    private(set) var problem: String?
    private(set) var isRunning = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Off in unit tests and the Simulator, where the unsigned build has no iCloud entitlement.
    static var canRun: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        #endif
    }

    private struct Meta: Codable {
        var engineState: CKSyncEngine.State.Serialization?
        var systemFields: [String: Data] = [:]
        var modified: [String: Date] = [:]
        var unresolved = SyncUnresolved()
    }

    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var meta = Meta()
    @ObservationIgnored private var lastMap: [String: SyncItem] = [:]
    @ObservationIgnored private var keys = SyncKeys()
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private let zoneID = CKRecordZone.ID(zoneName: "Hub", ownerName: CKCurrentUserDefaultName)
    @ObservationIgnored private let metaURL = URL.applicationSupportDirectory.appending(path: "sync.json")

    private var hub: HubStore { .shared }
    private var store: StateStore { .shared }

    private init() {
        if let d = try? Data(contentsOf: metaURL), let m = try? JSONDecoder().decode(Meta.self, from: d) { meta = m }
    }

    // MARK: Starting and stopping

    /// Called each time contacts are (re)read. The first call starts syncing.
    func contactsDidLoad(occasions: [Occasion], contacts: [ContactSnapshot]) {
        let built = SyncKeys.build(occasions: occasions, contacts: contacts)
        // An empty read (contacts access taken away) shouldn't make stars look deleted.
        if !(built.portable.isEmpty && !keys.portable.isEmpty) { keys = built }
        guard Self.canRun, Self.isEnabled else { return }
        if engine == nil {
            start()
        } else {
            flushDiff()
            // Stars, mutes and people notes from another phone that now match someone here.
            var unresolved = meta.unresolved
            applyQuietly { h, a in SyncItems.resolve(hub: &h, app: &a, keys: keys, unresolved: &unresolved) }
            meta.unresolved = unresolved
            flushDiff()
        }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            if Self.canRun, engine == nil { start() }
        } else {
            diffTask?.cancel()
            engine = nil
            isRunning = false
            hub.onChange = nil
            store.onChange = nil
        }
    }

    /// Pulls changes now, like when you come back to the app.
    func fetchNow() {
        guard let engine else { return }
        Task { try? await engine.fetchChanges() }
    }

    private func start() {
        var config = CKSyncEngine.Configuration(
            database: CKContainer.default().privateCloudDatabase,
            stateSerialization: meta.engineState,
            delegate: self)
        config.automaticallySync = true
        let firstRun = meta.engineState == nil
        engine = CKSyncEngine(config)
        isRunning = true
        hub.onChange = { [weak self] in self?.localChanged() }
        store.onChange = { [weak self] in self?.localChanged() }
        if firstRun {
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            uploadEverything()
        } else {
            lastMap = currentMap()
            // Anything changed while sync wasn't running (an older build, or sync switched off).
            flushDiff()
        }
        fetchNow()
    }

    private func uploadEverything() {
        lastMap = currentMap()
        engine?.state.add(pendingRecordZoneChanges: lastMap.keys.map { .saveRecord(recordID($0)) })
        saveMeta()
    }

    // MARK: Local changes

    private func currentMap() -> [String: SyncItem] {
        SyncItems.items(hub: hub.state, app: store.state, keys: keys, unresolved: meta.unresolved)
    }

    private func localChanged() {
        guard !applying else { return }
        // Typing in a note saves on every keystroke; send once it settles.
        diffTask?.cancel()
        diffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.flushDiff()
        }
    }

    private func flushDiff() {
        diffTask?.cancel()
        diffTask = nil
        guard let engine else { return }
        let current = currentMap()
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, item) in current where lastMap[name]?.data != item.data {
            meta.modified[name] = .now
            changes.append(.saveRecord(recordID(name)))
        }
        for name in lastMap.keys where current[name] == nil {
            meta.modified[name] = nil
            changes.append(.deleteRecord(recordID(name)))
        }
        lastMap = current
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        saveMeta()
    }

    /// Changes the stores without echoing the change back to iCloud.
    private func applyQuietly(_ change: (inout HubState, inout PersistedState) -> Void) {
        applying = true
        defer { applying = false }
        var h = hub.state
        var a = store.state
        change(&h, &a)
        let newHub = h
        let newApp = a
        hub.update { $0 = newHub }
        store.update { $0 = newApp }
        lastMap = currentMap()
    }

    // MARK: Records

    private func recordID(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID) }

    private func record(for name: String) -> CKRecord? {
        guard let item = lastMap[name] else { return nil }
        let record = meta.systemFields[name].flatMap(Self.decodeSystemFields)
            ?? CKRecord(recordType: Self.recordType, recordID: recordID(name))
        let env = SyncEnvelope(modified: meta.modified[name] ?? item.intrinsic, data: item.data)
        record["kind"] = item.kind.rawValue as CKRecordValue
        record["payload"] = SyncItems.encode(env) as CKRecordValue
        return record
    }

    private func incoming(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        flushDiff()
        let pending = Set(engine?.state.pendingRecordZoneChanges.compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName }
            return nil
        } ?? [])
        var unresolved = meta.unresolved
        applyQuietly { h, a in
            for r in records {
                let name = r.recordID.recordName
                meta.systemFields[name] = Self.encodeSystemFields(r)
                guard let kind = (r["kind"] as? String).flatMap(SyncKind.init(rawValue:)),
                      let data = r["payload"] as? Data,
                      let env = SyncItems.decode(SyncEnvelope.self, data) else { continue }
                // Our own newer edit is on its way up; keep it.
                if pending.contains(name), let mine = meta.modified[name], mine > env.modified { continue }
                meta.modified[name] = env.modified
                SyncItems.apply(kind, env.data, hub: &h, app: &a, keys: keys, unresolved: &unresolved)
            }
        }
        meta.unresolved = unresolved
        saveMeta()
    }

    private func deleted(_ names: [String]) {
        guard !names.isEmpty else { return }
        flushDiff()
        applyQuietly { h, _ in
            for name in names {
                SyncItems.remove(name, hub: &h)
                meta.systemFields[name] = nil
                meta.modified[name] = nil
            }
        }
        saveMeta()
    }

    private func failed(_ record: CKRecord, _ error: CKError) {
        let name = record.recordID.recordName
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return }
            let theirs = (server["payload"] as? Data).flatMap { SyncItems.decode(SyncEnvelope.self, $0) }?.modified ?? .distantPast
            let mine = meta.modified[name] ?? lastMap[name]?.intrinsic ?? .distantPast
            if theirs >= mine {
                incoming([server])
            } else {
                meta.systemFields[name] = Self.encodeSystemFields(server)
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
        case .zoneNotFound:
            meta.systemFields = [:]
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        case .unknownItem:
            meta.systemFields[name] = nil
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .operationCancelled:
            break // the engine retries these by itself
        case .notAuthenticated:
            problem = "Sign in to iCloud in Settings to sync."
        case .quotaExceeded:
            problem = "Your iCloud storage is full."
        default:
            problem = "Couldn't sync: \(error.localizedDescription)"
        }
        saveMeta()
    }

    // MARK: Saving our bookkeeping

    private func saveMeta() {
        guard let d = try? JSONEncoder().encode(meta) else { return }
        try? FileManager.default.createDirectory(at: metaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: metaURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func encodeSystemFields(_ r: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        r.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func decodeSystemFields(_ d: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: d) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let e):
            meta.engineState = e.stateSerialization
            saveMeta()
        case .accountChange(let e):
            switch e.changeType {
            case .signIn:
                problem = nil
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                uploadEverything()
            case .signOut, .switchAccounts:
                // Your data stays on this phone; it just stops matching the old account's records.
                meta.systemFields = [:]
                meta.modified = [:]
                saveMeta()
            @unknown default:
                break
            }
        case .fetchedDatabaseChanges(let e):
            if e.deletions.contains(where: { $0.zoneID == zoneID }) {
                meta.systemFields = [:]
                saveMeta()
            }
        case .fetchedRecordZoneChanges(let e):
            incoming(e.modifications.map(\.record))
            deleted(e.deletions.map(\.recordID.recordName))
            lastSynced = .now
            problem = nil
        case .sentRecordZoneChanges(let e):
            for r in e.savedRecords { meta.systemFields[r.recordID.recordName] = Self.encodeSystemFields(r) }
            for id in e.deletedRecordIDs { meta.systemFields[id.recordName] = nil }
            for f in e.failedRecordSaves { failed(f.record, f.error) }
            if e.failedRecordSaves.isEmpty { problem = nil }
            lastSynced = .now
            saveMeta()
        default:
            break
        }
    }

    fileprivate func batch(for pending: [CKSyncEngine.PendingRecordZoneChange]) -> (saves: [CKRecord], deletes: [CKRecord.ID], dropped: [CKSyncEngine.PendingRecordZoneChange]) {
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        var dropped: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending.prefix(200) {
            switch change {
            case .saveRecord(let id):
                if let r = record(for: id.recordName) { saves.append(r) } else { dropped.append(change) }
            case .deleteRecord(let id):
                deletes.append(id)
            @unknown default:
                break
            }
        }
        return (saves, deletes, dropped)
    }
}

extension CloudSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { self.handle(event) }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let (saves, deletes, dropped) = await MainActor.run { self.batch(for: pending) }
        if !dropped.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: dropped) }
        guard !saves.isEmpty || !deletes.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: saves, recordIDsToDelete: deletes)
    }
}
