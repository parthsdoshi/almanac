import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var tokenTask: Task<Void, Never>?

    var areEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The push-to-start token lets the server start a Live Activity while the
    /// app isn't running. It can change at any time, so keep listening.
    func observePushToStartToken(_ onToken: @escaping @MainActor (String) async -> Void) {
        guard tokenTask == nil else { return }
        tokenTask = Task {
            for await data in Activity<OccasionAttributes>.pushToStartTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                await onToken(hex)
            }
        }
    }

    /// iOS 26 can start a Live Activity at a set time with no server.
    static var canSchedule: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func isRunning(occasionID: String) -> Bool {
        Activity<OccasionAttributes>.activities.contains { $0.attributes.occasionID == occasionID }
    }

    /// Local start, used when there's no push server, and for the preview button.
    func start(_ occasion: Occasion) throws {
        let attributes = OccasionAttributes(
            occasionID: occasion.id,
            kind: occasion.kind.rawValue,
            names: occasion.firstNames
        )
        let state = OccasionAttributes.ContentState(headline: occasion.title)
        _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    /// Asks iOS 26+ to start the Live Activity at `date`, even if the app isn't
    /// running then. Only works while the app is in the foreground. Scheduled
    /// activities count toward the system's limit on simultaneous Live Activities.
    @available(iOS 26.0, *)
    func schedule(_ occasion: Occasion, at date: Date) throws {
        let attributes = OccasionAttributes(
            occasionID: occasion.id,
            kind: occasion.kind.rawValue,
            names: occasion.firstNames
        )
        let state = OccasionAttributes.ContentState(headline: occasion.title)
        _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil,
            style: .standard,
            alertConfiguration: AlertConfiguration(
                title: "\(occasion.title) is today",
                body: "Tap to message or call.",
                sound: .default
            ),
            start: date
        )
    }

    /// Occasion ids that have a Live Activity scheduled but not started yet.
    var pendingOccasionIDs: Set<String> {
        guard #available(iOS 26.0, *) else { return [] }
        return Set(Activity<OccasionAttributes>.activities
            .filter { $0.activityState == .pending }
            .map(\.attributes.occasionID))
    }

    func end(occasionID: String) async {
        for activity in Activity<OccasionAttributes>.activities where activity.attributes.occasionID == occasionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends activities whose occasion isn't today (or no longer exists / is muted).
    func endAll(except keep: Set<String>) async {
        for activity in Activity<OccasionAttributes>.activities where !keep.contains(activity.attributes.occasionID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Which upcoming occasions get a scheduled Live Activity (iOS 26+, no server).
///
/// Apple doesn't say how many scheduled activities an app may hold or how far
/// ahead, and scheduled ones count toward the limit on running ones. So keep a
/// few, near term, and top up every time the app comes to the foreground.
/// Anything not scheduled still gets the day-of notification.
enum LiveActivityPlanner {
    struct Planned: Equatable {
        let occasionID: String
        let start: Date
        /// Changes when the day or send hour changes, so a stale schedule is replaced.
        let key: String
    }

    static let maxScheduled = 3
    static let windowDays = 30

    static func plan(
        occasions: [Occasion],
        sendHour: Int,
        now: Date,
        calendar: Calendar,
        maxScheduled: Int = maxScheduled,
        windowDays: Int = windowDays
    ) -> [Planned] {
        guard let horizon = calendar.date(byAdding: .day, value: windowDays, to: now) else { return [] }
        let planned: [Planned] = occasions.compactMap { o in
            let next = Recurrence.next(o.date, onOrAfter: now, calendar: calendar)
            var c = calendar.dateComponents([.year, .month, .day], from: next)
            c.hour = sendHour
            c.minute = 0
            guard let start = calendar.date(from: c), start > now, start <= horizon else { return nil }
            return Planned(occasionID: o.id, start: start, key: "\(DayKey(next, calendar: calendar).rawValue)T\(sendHour)")
        }
        return Array(planned.sorted { ($0.start, $0.occasionID) < ($1.start, $1.occasionID) }.prefix(maxScheduled))
    }
}
