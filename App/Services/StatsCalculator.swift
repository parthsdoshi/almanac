import Foundation

struct OccasionStats: Equatable {
    enum Status: Equatable { case acted, missed, pending }

    struct Row: Identifiable, Equatable {
        var id: String { "\(occasionID)@\(day.rawValue)" }
        let occasionID: String
        let title: String
        let kind: OccasionKind
        let day: DayKey
        let status: Status
    }

    var acted = 0
    var missed = 0
    var pending = 0
    var rows: [Row] = []  // newest first

    /// Share of finished (acted or missed) occasions you acted on.
    var actedRate: Double? {
        let done = acted + missed
        return done == 0 ? nil : Double(acted) / Double(done)
    }
}

enum StatsCalculator {
    /// Counts each yearly instance between `trackingStart` and today for
    /// occasions that aren't muted. Today's instance is pending until acted on.
    static func compute(
        occasions: [Occasion],
        muted: Set<String>,
        actions: [ActionRecord],
        trackingStart: Date,
        today: Date,
        calendar: Calendar
    ) -> OccasionStats {
        let actedKeys = Set(actions.map { "\($0.occasionID)@\($0.instanceDay.rawValue)" })
        let start = calendar.startOfDay(for: trackingStart)
        let todayStart = calendar.startOfDay(for: today)
        let firstYear = calendar.component(.year, from: start)
        let lastYear = calendar.component(.year, from: todayStart)
        var stats = OccasionStats()

        for o in occasions where !muted.contains(o.id) {
            for year in firstYear...max(firstYear, lastYear) {
                let date = Recurrence.date(of: o.date, inYear: year, calendar: calendar)
                guard date >= start, date <= todayStart else { continue }
                let day = DayKey(date, calendar: calendar)
                let status: OccasionStats.Status
                if actedKeys.contains("\(o.id)@\(day.rawValue)") {
                    status = .acted; stats.acted += 1
                } else if date == todayStart {
                    status = .pending; stats.pending += 1
                } else {
                    status = .missed; stats.missed += 1
                }
                stats.rows.append(.init(occasionID: o.id, title: o.title, kind: o.kind, day: day, status: status))
            }
        }
        stats.rows.sort { $0.day > $1.day }
        return stats
    }

    /// Which year's instance an action belongs to. Acting up to a week early
    /// counts for the upcoming date, otherwise it's the most recent one (so a
    /// belated text still counts).
    static func instanceDay(for occasion: Occasion, actingAt now: Date, calendar: Calendar) -> DayKey {
        let next = Recurrence.next(occasion.date, onOrAfter: now, calendar: calendar)
        if Recurrence.daysUntil(next, from: now, calendar: calendar) <= 7 {
            return DayKey(next, calendar: calendar)
        }
        return DayKey(Recurrence.previous(occasion.date, onOrBefore: now, calendar: calendar), calendar: calendar)
    }
}
