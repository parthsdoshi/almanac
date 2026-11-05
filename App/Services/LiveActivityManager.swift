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
