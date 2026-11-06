import SwiftUI
import UserNotifications

@main
struct OccasionsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared
    @State private var hub = HubStore.shared
    @State private var workouts = WorkoutUI.shared

    init() {
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(hub)
                .environment(workouts)
                .task { await model.start() }
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .onChange(of: scenePhase) { _, phase in
                    // Picks up contact edits and time zone changes (travel) when you come back.
                    if phase == .active {
                        Task { await model.reload() }
                        CloudSync.shared.fetchNow()
                    }
                }
        }
        .backgroundTask(.appRefresh(AppConstants.refreshTaskID)) {
            await AppModel.shared.backgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // iCloud sync hears about changes from your other devices by silent push.
        application.registerForRemoteNotifications()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo["occasionID"] as? String else { return }
        await MainActor.run { AppModel.shared.show(occasionID: id) }
    }
}
