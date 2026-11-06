import EventKit
import Foundation

/// Apple Reminders and today's calendar, through EventKit. To-dos go to
/// Reminders so they sync everywhere and Siri sees them; the app keeps no
/// second list.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private let store = EKEventStore()

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let due: Date?
        let dueHasTime: Bool
        let done: Bool
        let listTitle: String
    }

    struct Event: Identifiable, Hashable {
        let id: String
        let title: String
        let start: Date
        let allDay: Bool
    }

    static var hasReminderAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    static var reminderAccessUndecided: Bool { EKEventStore.authorizationStatus(for: .reminder) == .notDetermined }
    static var hasCalendarAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestReminderAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    var defaultListTitle: String { store.defaultCalendarForNewReminders()?.title ?? "Reminders" }

    /// Adds a to-do to your default Reminders list.
    func add(_ title: String, due: Date?, hasTime: Bool, notes: String? = nil) async throws {
        if !Self.hasReminderAccess {
            guard await requestReminderAccess() else { throw ReminderError.noAccess }
        }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.notes = notes
        r.calendar = store.defaultCalendarForNewReminders()
        if let due {
            let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if hasTime { r.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        try store.save(r, commit: true)
    }

    /// Open reminders due by the end of today, plus ones finished today.
    func today(now: Date = .now) async -> [Item] {
        guard Self.hasReminderAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let open = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil))
        let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: nil))
        let items = (open + done).map { r in
            Item(id: r.calendarItemIdentifier, title: r.title ?? "",
                 due: r.dueDateComponents.flatMap { cal.date(from: $0) },
                 dueHasTime: r.dueDateComponents?.hour != nil,
                 done: r.isCompleted, listTitle: r.calendar?.title ?? "")
        }
        return items.sorted { a, b in
            if a.done != b.done { return !a.done }
            return (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
        }
    }

    func setDone(_ id: String, _ done: Bool) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted = done
        try? store.save(r, commit: true)
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    /// Today's calendar events still ahead, timed ones first.
    func eventsToday(now: Date = .now) -> [Event] {
        guard Self.hasCalendarAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && !($0.title ?? "").lowercased().contains("birthday") }
            .sorted { $0.startDate < $1.startDate }
            .map { Event(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate, allDay: $0.isAllDay) }
    }

    enum ReminderError: LocalizedError {
        case noAccess
        var errorDescription: String? {
            "Reminders access is off. You can turn it on in Settings > Privacy > Reminders."
        }
    }
}
