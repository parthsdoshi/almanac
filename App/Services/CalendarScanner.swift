import EventKit
import Foundation

struct BirthdaySuggestion: Identifiable, Hashable, Sendable {
    /// "normalized name|MM-dd", also the key stored when dismissed.
    let id: String
    let name: String
    let date: MonthDay
    /// Set when exactly one contact matches and it has no birthday yet, or
    /// when you pick a contact yourself.
    var contactID: String?
    var contactName: String?
    /// The calendar event it came from, so you can open it.
    var eventID: String? = nil
    var calendarTitle: String? = nil
    /// Set when you pick a contact that already has a birthday; adding replaces it.
    var existingBirthday: MonthDay? = nil
}

/// Pulls a person's name out of a birthday event title.
enum BirthdayTitleParser {
    private static let word = "(?:birthday|bday|b-day|b'day)"
    private static let patterns: [NSRegularExpression] = [
        "^(.+?)['’]s?\\s+\(word)$",           // Priya's Birthday, James' bday
        "^\(word)\\s*[:\\-–—]\\s*(.+)$",       // Birthday - Priya, Bday: Priya
        "^\(word)\\s+of\\s+(.+)$",            // Birthday of Priya
        "^(.+?)\\s+\(word)$",                 // Priya birthday
        "^happy\\s+\(word),?\\s+(.+?)!*$",     // Happy birthday Priya!
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let notNames: Set<String> = [
        "my", "your", "our", "his", "her", "their", "the", "a", "office", "team", "work",
    ]

    static func name(from title: String) -> String? {
        let cleaned = title
            .unicodeScalars.filter { !$0.properties.isEmojiPresentation && $0.properties.generalCategory != .otherSymbol }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’"))))
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        for regex in patterns {
            guard let match = regex.firstMatch(in: cleaned, range: range),
                  let r = Range(match.range(at: 1), in: cleaned) else { continue }
            let name = cleaned[r].trimmingCharacters(in: .whitespaces)
            let words = name.split(separator: " ")
            guard !name.isEmpty, words.count <= 3, !notNames.contains(name.lowercased()) else { return nil }
            return name
        }
        return nil
    }
}

enum SuggestionMatcher {
    struct Candidate: Hashable {
        let name: String
        let date: MonthDay
        var eventID: String? = nil
        var calendarTitle: String? = nil
    }

    static func suggestions(
        from candidates: [Candidate],
        contacts: [ContactSnapshot],
        dismissed: Set<String>
    ) -> [BirthdaySuggestion] {
        let index = NameIndex(contacts)
        var seen = Set<String>()
        var result: [BirthdaySuggestion] = []
        for c in candidates {
            let key = NameIndex.normalize(c.name) + "|" + String(format: "%02d-%02d", c.date.month, c.date.day)
            guard !dismissed.contains(key), seen.insert(key).inserted else { continue }
            let match = index.resolve(c.name)
            if match?.birthday != nil { continue } // already has one
            result.append(BirthdaySuggestion(
                id: key, name: c.name, date: MonthDay(month: c.date.month, day: c.date.day),
                contactID: match?.id,
                contactName: match.map { [$0.givenName, $0.familyName].filter { !$0.isEmpty }.joined(separator: " ") },
                eventID: c.eventID,
                calendarTitle: c.calendarTitle
            ))
        }
        return result.sorted { ($0.contactID == nil ? 1 : 0, $0.name) < ($1.contactID == nil ? 1 : 0, $1.name) }
    }
}

final class CalendarScanner {
    private let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// All-day events in the past and next year, excluding iOS's own Birthdays
    /// calendar (that one is generated from Contacts, so it adds nothing).
    func candidates(now: Date = .now, calendar: Calendar = .current) -> [SuggestionMatcher.Candidate] {
        let calendars = store.calendars(for: .event).filter { $0.type != .birthday }
        guard !calendars.isEmpty,
              let start = calendar.date(byAdding: .day, value: -366, to: now),
              let end = calendar.date(byAdding: .day, value: 366, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard event.isAllDay, let name = BirthdayTitleParser.name(from: event.title ?? "") else { return nil }
            let c = calendar.dateComponents([.month, .day], from: event.startDate)
            guard let date = MonthDay(components: c) else { return nil }
            return .init(name: name, date: date, eventID: event.eventIdentifier, calendarTitle: event.calendar?.title)
        }
    }

    func event(id: String) -> EKEvent? {
        store.event(withIdentifier: id)
    }
}
