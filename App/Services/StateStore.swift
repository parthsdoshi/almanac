import Foundation
import Observation

/// JSON file in Application Support. Small enough that rewriting it on every
/// change is fine. Readable after first unlock so background refresh and the
/// Mute intent can use it while the phone is locked.
@MainActor
@Observable
final class StateStore {
    static let shared = StateStore()

    private(set) var state: PersistedState
    @ObservationIgnored private let url: URL
    /// Called after every change, for iCloud sync.
    @ObservationIgnored var onChange: (() -> Void)?

    init(url: URL = StateStore.defaultURL()) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState()
            save() // pin deviceID and trackingStart on first launch
        }
    }

    func update(_ change: (inout PersistedState) -> Void) {
        change(&state)
        save()
        onChange?()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            assertionFailure("Couldn't save state: \(error)")
        }
    }

    nonisolated static func defaultURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "state.json")
    }
}
