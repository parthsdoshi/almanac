import SwiftUI
import UserNotifications

@main
struct OccasionsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    init() {
        Appearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .onChange(of: scenePhase) { _, phase in
                    // Picks up contact edits and time zone changes (travel) when you come back.
                    if phase == .active { Task { await model.reload() } }
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
