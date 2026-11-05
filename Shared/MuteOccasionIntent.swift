import ActivityKit
import AppIntents
import Foundation

/// The Live Activity's "Mute" button.
///
/// `LiveActivityIntent` runs in the app's process (iOS launches it in the
/// background if needed), which is why this file is in both targets but only
/// does work when compiled into the app.
struct MuteOccasionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute occasion forever"
    static var description = IntentDescription("Stops reminders and Live Activities for this occasion.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Occasion ID")
    var occasionID: String

    init() {}

    init(occasionID: String) {
        self.occasionID = occasionID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await AppModel.shared.mute(occasionID: occasionID)
        #endif
        return .result()
    }
}
