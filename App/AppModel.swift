import BackgroundTasks
import Foundation
import MessageUI
import Observation
import UIKit

enum AppConstants {
    /// Must match BGTaskSchedulerPermittedIdentifiers in project.yml.
    static let refreshTaskID = "occasions.refresh"
}

/// A prefilled text waiting to be shown in the Messages compose sheet.
struct ComposeRequest: Identifiable, Equatable {
    let id = UUID()
    let occasionID: String
    let instanceDay: DayKey
    let recipients: [String]
    let body: String
}

/// For a couple: which of them to call.
struct CallChoice: Identifiable, Equatable {
    struct Option: Identifiable, Equatable {
        var id: String { number }
        let name: String
        let number: String
    }
    let id = UUID()
    let occasionID: String
    let instanceDay: DayKey
    let options: [Option]
}

struct UpcomingItem: Identifiable, Hashable {
    var id: String { occasion.id }
    let occasion: Occasion
    let nextDate: Date
    let daysUntil: Int
    /// Age they turn / years married, when the year is known.
    let years: Int?
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Tab: Hashable { case upcoming, stats, suggestions, settings }

    // UI state
    var selectedTab: Tab = .upcoming
    var upcomingPath: [String] = []
    var composeRequest: ComposeRequest?
    var callChoice: CallChoice?
    var alertMessage: String?
    /// Goes up each time you text or call someone from the app. The confetti burst watches it.
    private(set) var celebrations = 0

    // Data
    private(set) var contactsAccess = ContactsService.currentAccess()
    private(set) var occasions: [Occasion] = []
    private(set) var suggestions: [BirthdaySuggestion] = []
    private(set) var hasScannedCalendar = false
    private(set) var serverStatus: String?

    let store = StateStore.shared
    @ObservationIgnored private let contacts = ContactsService()
    @ObservationIgnored private let notifications = NotificationScheduler()
    @ObservationIgnored private let liveActivities = LiveActivityManager()
    @ObservationIgnored private let calendarScanner = CalendarScanner()
    @ObservationIgnored let server = ServerClient.fromBundle()
    @ObservationIgnored private var snapshots: [ContactSnapshot] = []
    @ObservationIgnored private var started = false
    /// Kept alive across reloads so the preview doesn't vanish when you come back to the app.
    @ObservationIgnored private var previewOccasionID: String?
    private var calendar: Calendar { .current }

    var settings: Settings { store.state.settings }

    var activeOccasions: [Occasion] {
        occasions.filter { store.state.muted[$0.id] == nil }
    }

    var upcoming: [UpcomingItem] {
        let now = Date()
        return activeOccasions.map { o in
            let next = Recurrence.next(o.date, onOrAfter: now, calendar: calendar)
            return UpcomingItem(
                occasion: o,
                nextDate: next,
                daysUntil: Recurrence.daysUntil(next, from: now, calendar: calendar),
                years: Recurrence.yearsSince(o.date, atYear: calendar.component(.year, from: next))
            )
        }
        .sorted { ($0.daysUntil, $0.occasion.title) < ($1.daysUntil, $1.occasion.title) }
    }

    var stats: OccasionStats {
        StatsCalculator.compute(
            occasions: occasions,
            muted: Set(store.state.muted.keys),
            actions: store.state.actions,
            trackingStart: store.state.trackingStart,
            today: .now,
            calendar: calendar
        )
    }

    func occasion(id: String) -> Occasion? {
        occasions.first { $0.id == id }
    }

    func actions(for occasionID: String) -> [ActionRecord] {
        store.state.actions.filter { $0.occasionID == occasionID }.sorted { $0.at > $1.at }
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        liveActivities.observePushToStartToken { [weak self] token in
            guard let self else { return }
            if self.store.state.pushToStartToken != token {
                self.store.update { $0.pushToStartToken = token }
            }
            await self.syncServer(force: false)
        }
        await reload()
    }

    func requestPermissions() async {
        do {
            _ = try await contacts.requestAccess()
        } catch {
            alertMessage = error.localizedDescription
        }
        _ = await notifications.requestAuthorization()
        await reload()
    }

    /// Re-reads Contacts and brings notifications, Live Activities and the server up to date.
    func reload() async {
        contactsAccess = ContactsService.currentAccess()
        guard contactsAccess.canRead else { return }
        do {
            snapshots = try await Task.detached(priority: .userInitiated) {
                try ContactsService().fetchSnapshots()
            }.value
            var built = OccasionBuilder.build(from: snapshots)
            if !settings.includeAnniversaries { built.removeAll { $0.kind == .anniversary } }
            occasions = built
        } catch {
            alertMessage = "Couldn't read contacts: \(error.localizedDescription)"
            return
        }
        await refreshSchedules()
        scheduleBackgroundRefresh()
    }

    func backgroundRefresh() async {
        await reload()
    }

    private func refreshSchedules() async {
        let active = activeOccasions
        let items = NotificationPlanner.plan(
            occasions: active,
            settings: settings,
            includeDayOf: !server.isConfigured,  // the server's Live Activity alert covers day-of
            now: .now,
            calendar: calendar
        )
        await notifications.replace(with: items)
        await updateLiveActivities(active: active)
        await syncServer(force: false)
    }

    /// Ends activities that aren't for today. Without a server, also starts
    /// today's activities locally (once per occasion per day). With a server we
    /// never start locally, or you'd get duplicates when the push lands.
    private func updateLiveActivities(active: [Occasion]) async {
        let now = Date()
        let todays = active.filter {
            Recurrence.daysUntil(Recurrence.next($0.date, onOrAfter: now, calendar: calendar), from: now, calendar: calendar) == 0
        }
        var keep = Set(todays.map(\.id))
        if let previewOccasionID { keep.insert(previewOccasionID) }
        await liveActivities.endAll(except: keep)

        guard !server.isConfigured, liveActivities.areEnabled else { return }
        let today = DayKey(now, calendar: calendar).rawValue
        for o in todays {
            let key = "\(o.id)@\(today)"
            guard !store.state.startedActivityKeys.contains(key), !liveActivities.isRunning(occasionID: o.id) else { continue }
            do {
                try liveActivities.start(o)
                store.update { s in
                    s.startedActivityKeys = s.startedActivityKeys.filter { $0.hasSuffix("@\(today)") }
                    s.startedActivityKeys.insert(key)
                }
            } catch {
                // Usually the app isn't in the foreground; try again next launch.
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Server

    func syncServer(force: Bool) async {
        guard server.isConfigured else { return }
        guard let token = store.state.pushToStartToken else {
            serverStatus = "Waiting for a push token from iOS"
            return
        }
        let payload = ServerClient.DevicePayload(
            pushToStartToken: token,
            apnsEnvironment: ServerClient.apnsEnvironment,
            timeZone: TimeZone.current.identifier,
            sendHour: settings.sendHour,
            occasions: activeOccasions.map {
                .init(id: $0.id, kind: $0.kind.rawValue, names: $0.firstNames, month: $0.date.month, day: $0.date.day)
            }
        )
        let fingerprint = payload.fingerprint
        guard force || fingerprint != store.state.lastSyncedHash else { return }
        do {
            try await server.putDevice(id: store.state.deviceID, payload: payload)
            store.update {
                $0.lastSyncedHash = fingerprint
                $0.lastSyncedAt = .now
            }
            serverStatus = nil
        } catch {
            serverStatus = error.localizedDescription
        }
    }

    func sendServerTest() async {
        do {
            await syncServer(force: true)
            try await server.sendTest(deviceID: store.state.deviceID)
            alertMessage = "Sent. The Live Activity should show on your Lock Screen in a few seconds."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func previewLiveActivity() {
        guard let o = upcoming.first?.occasion else {
            alertMessage = "No occasions to preview."
            return
        }
        do {
            try liveActivities.start(o)
            previewOccasionID = o.id
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: Settings & mute

    func updateSettings(_ change: (inout Settings) -> Void) {
        let before = settings
        store.update { change(&$0.settings) }
        // Message templates don't affect schedules, so don't resync on every keystroke.
        guard settings.leadDays != before.leadDays
            || settings.sendHour != before.sendHour
            || settings.includeAnniversaries != before.includeAnniversaries else { return }
        Task {
            if settings.includeAnniversaries != before.includeAnniversaries {
                await reload()
            } else {
                await refreshSchedules()
            }
        }
    }

    /// Called from the app and from the Live Activity's Mute button.
    func mute(occasionID: String) async {
        if occasions.isEmpty { await reload() }
        let title = occasion(id: occasionID)?.title ?? "Muted occasion"
        store.update { $0.muted[occasionID] = title }
        await liveActivities.end(occasionID: occasionID)
        if previewOccasionID == occasionID { previewOccasionID = nil }
        upcomingPath.removeAll { $0 == occasionID }
        await refreshSchedules()
    }

    func unmute(occasionID: String) async {
        store.update { $0.muted[occasionID] = nil }
        await refreshSchedules()
    }

    // MARK: Deep links & actions

    func handle(url: URL) async {
        guard let link = DeepLink.parse(url) else { return }
        if occasions.isEmpty { await reload() }
        guard let o = occasion(id: link.occasionID) else {
            alertMessage = "That contact isn't in your contacts anymore."
            return
        }
        switch link.action {
        case .open: show(occasionID: o.id)
        case .message: beginMessage(o)
        case .call: beginCall(o)
        }
    }

    func show(occasionID: String) {
        if let title = store.state.muted[occasionID] {
            alertMessage = "\(title) is muted. You can unmute it in Settings."
            return
        }
        selectedTab = .upcoming
        upcomingPath = [occasionID]
    }

    func beginMessage(_ o: Occasion) {
        let recipients = o.people.compactMap(\.phoneNumbers.first)
        guard !recipients.isEmpty else {
            alertMessage = "No phone number for \(Names.join(o.firstNames))."
            return
        }
        let template = o.kind == .birthday ? settings.birthdayTemplate : settings.anniversaryTemplate
        let body = template
            .replacingOccurrences(of: "{name}", with: o.firstNames.first ?? "")
            .replacingOccurrences(of: "{names}", with: Names.join(o.firstNames))
        let day = StatsCalculator.instanceDay(for: o, actingAt: .now, calendar: calendar)

        if MFMessageComposeViewController.canSendText() {
            composeRequest = ComposeRequest(occasionID: o.id, instanceDay: day, recipients: recipients, body: body)
        } else if let url = Self.smsURL(recipients: recipients, body: body) {
            // No compose sheet (e.g. Simulator). We can't tell if it was sent, so count the attempt.
            UIApplication.shared.open(url)
            record(.messageSent, occasionID: o.id, day: day)
        }
    }

    func didFinishCompose(_ request: ComposeRequest, result: MessageComposeResult) {
        composeRequest = nil
        if result == .sent {
            record(.messageSent, occasionID: request.occasionID, day: request.instanceDay)
        }
    }

    func beginCall(_ o: Occasion) {
        let options = o.people.compactMap { p in
            p.phoneNumbers.first.map { CallChoice.Option(name: p.firstName, number: $0) }
        }
        let day = StatsCalculator.instanceDay(for: o, actingAt: .now, calendar: calendar)
        switch options.count {
        case 0: alertMessage = "No phone number for \(Names.join(o.firstNames))."
        case 1: call(options[0], occasionID: o.id, day: day)
        default: callChoice = CallChoice(occasionID: o.id, instanceDay: day, options: options)
        }
    }

    func call(_ option: CallChoice.Option, occasionID: String, day: DayKey) {
        callChoice = nil
        let digits = option.number.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return }
        // iOS shows its own "Call …?" confirmation; nothing dials without your tap.
        UIApplication.shared.open(url)
        record(.call, occasionID: occasionID, day: day)
    }

    private func record(_ kind: ActionRecord.Kind, occasionID: String, day: DayKey) {
        store.update { s in
            guard !s.actions.contains(where: { $0.occasionID == occasionID && $0.instanceDay == day && $0.kind == kind }) else { return }
            s.actions.append(ActionRecord(occasionID: occasionID, instanceDay: day, kind: kind, at: .now))
        }
        celebrations += 1
        Task { await liveActivities.end(occasionID: occasionID) }
    }

    /// Fallback when the compose sheet isn't available. `sms:/open?addresses=` opens a group thread.
    static func smsURL(recipients: [String], body: String) -> URL? {
        let numbers = recipients.map { $0.filter { $0.isNumber || $0 == "+" } }
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let base = numbers.count == 1
            ? "sms:\(numbers[0])"
            : "sms:/open?addresses=\(numbers.joined(separator: ","))"
        return URL(string: "\(base)&body=\(encodedBody)")
    }

    // MARK: Calendar suggestions

    func scanCalendar() async {
        do {
            if !CalendarScanner.hasAccess {
                guard try await calendarScanner.requestAccess() else {
                    alertMessage = "Calendar access is off. You can turn it on in Settings > Privacy > Calendars."
                    return
                }
            }
            if snapshots.isEmpty { await reload() }
            let candidates = calendarScanner.candidates()
            suggestions = SuggestionMatcher.suggestions(
                from: candidates, contacts: snapshots, dismissed: store.state.dismissedSuggestions)
            hasScannedCalendar = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func accept(_ s: BirthdaySuggestion) async {
        do {
            if let id = s.contactID {
                try contacts.setBirthday(s.date, contactID: id)
            } else {
                try contacts.createContact(name: s.name, birthday: s.date)
            }
            suggestions.removeAll { $0.id == s.id }
            await reload()
        } catch {
            alertMessage = "Couldn't save to Contacts: \(error.localizedDescription)"
        }
    }

    func dismiss(_ s: BirthdaySuggestion) {
        store.update { $0.dismissedSuggestions.insert(s.id) }
        suggestions.removeAll { $0.id == s.id }
    }
}
