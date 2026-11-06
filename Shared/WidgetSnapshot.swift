import Foundation

/// What the home screen widget shows. The app writes it into the App Group
/// container every time it refreshes its schedules; the widget only reads it.
///
/// Holds first names, the kind and the month/day of each unmuted occasion.
/// No contact identifiers or phone numbers.
struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Hashable, Sendable, Identifiable {
        let id: String
        let kind: OccasionKind
        /// "Priya" or "Alex & Sam".
        let names: String
        let month: Int
        let day: Int
        /// Birth or wedding year, when the contact has one.
        let originYear: Int?
    }

    /// The widget kind the app reloads after writing.
    static let widgetKind = "NextOccasion"

    var items: [Item]
    var writtenAt: Date

    /// Set in both Info.plists from APP_GROUP_ID (Config/Base.xcconfig).
    static var appGroupID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var fileURL: URL? {
        guard let group = appGroupID,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return dir.appending(path: "widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The soonest occasions on or after `date`'s day, soonest first.
    func upcoming(from date: Date, limit: Int, calendar: Calendar = .current) -> [Upcoming] {
        items.map { item in
            let next = item.next(onOrAfter: date, calendar: calendar)
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: next).day ?? 0
            let year = calendar.component(.year, from: next)
            let years = item.originYear.flatMap { year > $0 ? year - $0 : nil }
            return Upcoming(item: item, date: next, daysUntil: days, years: years)
        }
        .sorted { ($0.daysUntil, $0.item.names) < ($1.daysUntil, $1.item.names) }
        .prefix(limit)
        .map { $0 }
    }

    struct Upcoming: Hashable, Identifiable {
        let item: Item
        let date: Date
        let daysUntil: Int
        /// "turns 31" or "10th anniversary", when the year is known.
        let years: Int?
        var id: String { item.id }
    }
}

extension WidgetSnapshot.Item {
    /// Same rule as Recurrence in the app: Feb 29 falls on Feb 28 in other years,
    /// and an out-of-range day is clamped to the month's last day.
    func next(onOrAfter reference: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: reference)
        let year = calendar.component(.year, from: start)
        let thisYear = date(inYear: year, calendar: calendar)
        return thisYear >= start ? thisYear : date(inYear: year + 1, calendar: calendar)
    }

    private func date(inYear year: Int, calendar: Calendar) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let last = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, last)))!
    }
}
