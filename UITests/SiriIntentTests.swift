import AppIntents
import AppIntentsTesting
import XCTest

/// Runs the app's intents the way Siri and Shortcuts do (iOS 27's AppIntentsTesting),
/// against the installed app.
final class SiriIntentTests: XCTestCase {
    private var bundleID: String {
        Bundle(for: SiriIntentTests.self).object(forInfoDictionaryKey: "AppBundleID") as? String ?? ""
    }

    override func setUp() {
        continueAfterFailure = false
        // Opens once so iOS registers the app's intents and entities.
        XCUIApplication().launch()
    }

    func testJotSavesANoteThatSiriCanFind() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Needs iOS 27") }
        let definitions = IntentDefinitions(bundleIdentifier: bundleID)
        let line = "pasta maker for the kitchen \(UUID().uuidString.prefix(6))"
        let result = try await definitions.intents["JotIntent"].makeIntent(text: line).run()
        let said: String = try result.value
        XCTAssertEqual(said, "Saved it as a note.")

        let notes = try await definitions.entities["NoteEntity"].entities(matching: "pasta maker")
        XCTAssertFalse(notes.isEmpty)
    }

    func testOccasionsAnswerQueries() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Needs iOS 27") }
        // A fresh Simulator has few contacts, so this checks the query runs, not what it finds.
        _ = try await IntentDefinitions(bundleIdentifier: bundleID).entities["OccasionEntity"].suggestedEntities()
    }
}
