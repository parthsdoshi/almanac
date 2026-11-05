import CryptoKit
import Foundation

/// A month and day, with the year when the contact has one.
struct MonthDay: Codable, Hashable, Sendable {
    var month: Int
    var day: Int
    var year: Int?

    init(month: Int, day: Int, year: Int? = nil) {
        self.month = month
        self.day = day
        self.year = year
    }

    /// Returns nil for incomplete or nonsense components.
    /// Year 1604 is the placeholder iOS uses for "no year" birthdays, so it's dropped.
    init?(components: DateComponents) {
        guard let m = components.month, let d = components.day,
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        month = m
        day = d
        if let y = components.year, y > 1604, y < 3000 {
            year = y
        } else {
            year = nil
        }
    }
}

struct Person: Codable, Hashable, Identifiable, Sendable {
    var id: String { contactID }
    let contactID: String
    let givenName: String
    let familyName: String
    /// Best number first (iPhone, then mobile, then the rest). Never persisted or uploaded.
    let phoneNumbers: [String]

    var firstName: String {
        givenName.isEmpty ? familyName : givenName
    }

    var fullName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct Occasion: Identifiable, Hashable, Sendable {
    let id: String
    let kind: OccasionKind
    let people: [Person]
    let date: MonthDay

    init(kind: OccasionKind, people: [Person], date: MonthDay, discriminator: Int = 0) {
        self.kind = kind
        self.people = people
        self.date = date
        self.id = Self.makeID(kind: kind, contactIDs: people.map(\.contactID), discriminator: discriminator)
    }

    var firstNames: [String] { people.map(\.firstName) }
    var title: String { Names.headline(kind: kind, names: firstNames) }

    /// Stable and opaque: a hash of the kind and contact identifiers. The date is
    /// deliberately left out so editing a birthday keeps its mute and stats.
    /// The server only ever sees this hash, never contact identifiers.
    static func makeID(kind: OccasionKind, contactIDs: [String], discriminator: Int = 0) -> String {
        var parts = [kind.rawValue] + contactIDs.sorted()
        if discriminator > 0 { parts.append(String(discriminator)) }
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the user did about an occasion on a given year's date.
struct ActionRecord: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Only recorded when Messages reports the text was sent.
        case messageSent
        /// Recorded when the call prompt is opened. iOS doesn't tell apps whether the call happened.
        case call
    }

    let occasionID: String
    let instanceDay: DayKey
    let kind: Kind
    let at: Date
}

/// A calendar day as "yyyy-MM-dd", independent of time zone once created.
struct DayKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var description: String { rawValue }
    static func < (a: DayKey, b: DayKey) -> Bool { a.rawValue < b.rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}
