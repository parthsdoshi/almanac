import Foundation
import UserNotifications

/// Pure planning, separate from UNUserNotificationCenter so it can be tested.
enum NotificationPlanner {
    struct Item: Equatable {
        let identifier: String
        let occasionID: String
        let fireDate: Date
        let fireComponents: DateComponents
        let title: String
        let body: String
    }

    /// iOS keeps at most 64 pending local notifications per app. We use 60 and
    /// rely on launches and background refresh to roll the window forward.
    static let limit = 60

    static func plan(
        occasions: [Occasion],
        settings: Settings,
        includeDayOf: Bool,
        now: Date,
        calendar: Calendar
    ) -> [Item] {
        var items: [Item] = []
        for o in occasions {
            let next = Recurrence.next(o.date, onOrAfter: now, calendar: calendar)
            let dateText = next.formatted(.dateTime.month(.abbreviated).day())

            if settings.leadDays > 0,
               let lead = calendar.date(byAdding: .day, value: -settings.leadDays, to: next) {
                let when = settings.leadDays == 1 ? "tomorrow" : "in \(settings.leadDays) days"
                add(&items, o, kind: "lead", day: lead, hour: settings.sendHour, now: now, calendar: calendar,
                    title: "\(o.title) is \(when)", body: "\(dateText). Tap to plan a message.")
            }
            if includeDayOf {
                add(&items, o, kind: "dayof", day: next, hour: settings.sendHour, now: now, calendar: calendar,
                    title: "\(o.title) is today", body: "Tap to message or call.")
            }
        }
        return Array(items.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    private static func add(
        _ items: inout [Item], _ o: Occasion, kind: String, day: Date, hour: Int,
        now: Date, calendar: Calendar, title: String, body: String
    ) {
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        c.minute = 0
        guard let fire = calendar.date(from: c), fire > now else { return }
        items.append(Item(
            identifier: "\(NotificationScheduler.prefix)\(o.id).\(kind).\(DayKey(day, calendar: calendar).rawValue)",
            occasionID: o.id, fireDate: fire, fireComponents: c, title: title, body: body
        ))
    }
}

struct NotificationScheduler {
    static let prefix = "occasion."
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all of our pending notifications with `items`.
    /// Triggers use wall-clock components without a time zone, so they fire at
    /// the local hour wherever the phone is.
    func replace(with items: [NotificationPlanner.Item]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.occasionID
            content.userInfo = ["occasionID": item.occasionID]
            let trigger = UNCalendarNotificationTrigger(dateMatching: item.fireComponents, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}
