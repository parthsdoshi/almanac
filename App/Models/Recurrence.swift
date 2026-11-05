import Foundation

/// Yearly date math. Feb 29 is observed on Feb 28 in non-leap years, and any
/// out-of-range day (bad data like Apr 31) is clamped to the month's last day.
/// server/src/schedule.js applies the same rule.
enum Recurrence {
    static func date(of md: MonthDay, inYear year: Int, calendar: Calendar) -> Date {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: md.month, day: 1))!
        let lastDay = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        return calendar.date(from: DateComponents(year: year, month: md.month, day: min(md.day, lastDay)))!
    }

    /// The next occurrence on or after the start of `reference`'s day.
    static func next(_ md: MonthDay, onOrAfter reference: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: reference)
        let year = calendar.component(.year, from: start)
        let thisYear = date(of: md, inYear: year, calendar: calendar)
        return thisYear >= start ? thisYear : date(of: md, inYear: year + 1, calendar: calendar)
    }

    /// The most recent occurrence on or before `reference`'s day.
    static func previous(_ md: MonthDay, onOrBefore reference: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: reference)
        let year = calendar.component(.year, from: start)
        let thisYear = date(of: md, inYear: year, calendar: calendar)
        return thisYear <= start ? thisYear : date(of: md, inYear: year - 1, calendar: calendar)
    }

    static func daysUntil(_ date: Date, from reference: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "turns 31" / "10th anniversary" number for the occurrence in `year`, if the original year is known.
    static func yearsSince(_ md: MonthDay, atYear year: Int) -> Int? {
        guard let origin = md.year, year > origin else { return nil }
        return year - origin
    }
}
