import Foundation
import Observation

// Everything the hub keeps that isn't a birthday: notes, what you know about
// people, and the workout log. One JSON file next to state.json, so the
// occasions code doesn't change.

struct Note: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var body: String
    var tags: [String] = []
    var created = Date()
    var updated = Date()
}

/// A line you jotted about someone, keyed by their contact card.
struct PersonNote: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var contactID: String
    var text: String
    var created = Date()
    /// The person's full name when it was synced, so another phone (with different contact ids) can find them.
    var personName: String?
}

/// One logged set. Field names match the web tracker's backup file.
struct LoggedSet: Codable, Hashable, Sendable {
    var exerciseId: String
    var name: String
    var blockLabel: String
    var setNumber: Int
    var weight: Double
    var reps: Int
}

struct WorkoutSession: Codable, Identifiable, Hashable, Sendable {
    /// ISO 8601 with fractional seconds, as the web app writes it.
    var date: String
    var workout: WorkoutID
    var durationSec: Int
    var sets: [LoggedSet]
    var note: String?
    var exerciseNotes: [String: String]?

    var id: String { date }
    var startDate: Date { WorkoutDates.parse(date) ?? .distantPast }
}

struct BodyweightEntry: Codable, Hashable, Sendable {
    /// Local calendar date, YYYY-MM-DD.
    var date: String
    var lb: Double
}

struct WorkoutLog: Codable, Hashable, Sendable {
    var weights: [String: Double] = [:]
    var history: [WorkoutSession] = []
    /// Graduations: base exercise id -> successor id.
    var overrides: [String: String] = [:]
    var bodyweight: [BodyweightEntry] = []

    func weight(for ex: Exercise) -> Double { weights[ex.id] ?? ex.defaultWeight }
}

struct HubState: Codable, Sendable {
    var notes: [Note] = []
    var personNotes: [PersonNote] = []
    var workouts = WorkoutLog()

    init() {}

    // Tolerant decoding, so adding a field later never wipes the file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = (try? c.decode([Note].self, forKey: .notes)) ?? []
        personNotes = (try? c.decode([PersonNote].self, forKey: .personNotes)) ?? []
        workouts = (try? c.decode(WorkoutLog.self, forKey: .workouts)) ?? WorkoutLog()
    }
}

enum WorkoutDates {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date? { withFraction.date(from: s) ?? plain.date(from: s) }
    static func string(_ d: Date) -> String { withFraction.string(from: d) }

    static func dayString(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

@MainActor
@Observable
final class HubStore {
    static let shared = HubStore()

    private(set) var state: HubState
    @ObservationIgnored private let url: URL
    /// Called after every change, for iCloud sync.
    @ObservationIgnored var onChange: (() -> Void)?

    init(url: URL = HubStore.defaultURL()) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(HubState.self, from: data) {
            state = decoded
        } else {
            state = HubState()
        }
    }

    func update(_ change: (inout HubState) -> Void) {
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
            assertionFailure("Couldn't save hub: \(error)")
        }
    }

    nonisolated static func defaultURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "hub.json")
    }

    // MARK: Notes

    func notes(for contactIDs: [String]) -> [PersonNote] {
        state.personNotes.filter { contactIDs.contains($0.contactID) }.sorted { $0.created > $1.created }
    }

    func addPersonNote(_ text: String, contactID: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update { $0.personNotes.append(PersonNote(contactID: contactID, text: t)) }
    }

    func deletePersonNote(_ id: UUID) {
        update { $0.personNotes.removeAll { $0.id == id } }
    }

    @discardableResult
    func addNote(title: String = "", body: String) -> Note {
        let note = Note(title: title, body: body)
        update { $0.notes.insert(note, at: 0) }
        return note
    }

    func saveNote(_ note: Note) {
        update { s in
            var n = note
            n.updated = .now
            if let i = s.notes.firstIndex(where: { $0.id == note.id }) { s.notes[i] = n } else { s.notes.insert(n, at: 0) }
        }
    }

    func deleteNote(_ id: UUID) {
        update { $0.notes.removeAll { $0.id == id } }
    }
}
