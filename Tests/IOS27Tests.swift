import Foundation
import Testing
@testable import Occasions
#if canImport(Evaluations)
import Evaluations
#endif
#if canImport(AppIntentsTesting)
import AppIntents
import AppIntentsTesting
#endif

// MARK: Photo Jot guards (every iOS)

@Suite struct PhotoReaderTests {
    private let invite = [
        "Together with their families",
        "Sam Rivera & Lee Park",
        "request the pleasure of your company",
        "Saturday, January 16, 2027",
        "Kindly RSVP by December 1, 2026",
    ]

    @Test func keepsItemsThatMatchThePrint() {
        let kept = PhotoReader.keep(["RSVP to Sam and Lee's wedding by December 1, 2026"], printed: invite)
        #expect(kept == ["RSVP to Sam and Lee's wedding by December 1, 2026"])
    }

    @Test func dropsItemsTheModelMadeUp() {
        #expect(PhotoReader.keep(["Book a hotel in Paris"], printed: invite).isEmpty)
    }

    @Test func dropsADateThatIsntPrinted() {
        let kept = PhotoReader.keep(["Buy a gift for Sam and Lee by December 20, 2026"], printed: invite)
        #expect(kept == ["Buy a gift for Sam and Lee"])
    }

    @Test func rulesPickDatedAndAskingLines() {
        #expect(PhotoReader.ruleLines(invite) == ["Saturday, January 16, 2027", "Kindly RSVP by December 1, 2026"])
    }

    @Test func rulesFallBackToTheWholePrint() {
        #expect(PhotoReader.ruleLines(["Thank you", "for the lovely gift"]) == ["Thank you for the lovely gift"])
    }
}

// MARK: Siri Jot planning (every iOS, rules only on a Simulator)

@Suite @MainActor struct JotFilerTests {
    @Test func severalThingsBecomeSeveralReminders() async {
        let items = await JotFiler.plan("call mom, buy milk and renew my passport", contacts: [])
        #expect(items.count == 3)
        for item in items {
            guard case .reminder = item else { Issue.record("expected a reminder, got \(item)"); return }
        }
    }

    @Test func aThoughtBecomesANote() async {
        let items = await JotFiler.plan("pasta maker for the kitchen", contacts: [])
        #expect(items == [.note("pasta maker for the kitchen")])
    }

    @Test func nothingPlansNothing() async {
        #expect(await JotFiler.plan("   ", contacts: []).isEmpty)
    }
}

// MARK: Evaluations (iOS 27): how well Jot splits a line into to-dos

#if canImport(Evaluations)
@available(iOS 27.0, *)
struct JotSplitSample: SampleProtocol {
    let input: String
    let expected: Int?
}

/// Runs the same split Jot uses (the on-device model when the device has it,
/// the rules otherwise) and checks the number of to-dos it finds.
@available(iOS 27.0, *)
struct JotSplitEvaluation: Evaluation {
    var name: String { "Jot split" }

    var dataset: ArrayLoader<JotSplitSample> {
        [
            JotSplitSample(input: "I need to call mom, buy milk and renew my passport", expected: 3),
            JotSplitSample(input: "email Dan, pay rent, and book flights", expected: 3),
            JotSplitSample(input: "call the bank and pay the bill", expected: 2),
            JotSplitSample(input: "buy salt and pepper", expected: 1),
            JotSplitSample(input: "- milk\n- eggs\n- bread", expected: 3),
            JotSplitSample(input: "call mom on Friday, Nov 7", expected: 1),
        ]
    }

    nonisolated(nonsending) func subject(from sample: JotSplitSample) async throws -> ModelSubject<Int> {
        let pieces = await ModelCapture.todos(in: sample.input) ?? RuleCapture.split(sample.input)
        return ModelSubject(value: max(pieces.count, 1))
    }

    var evaluators: Evaluators {
        Evaluator<JotSplitSample> { sample, subject in
            subject.value == sample.expected
                ? Metric("pieces").passing()
                : Metric("pieces").failing(rationale: "got \(subject.value), wanted \(sample.expected ?? 0)")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Metric("pieces"))
    }
}

@Suite struct JotSplitEvaluationTests {
    @Test func splitsMostLinesRight() async throws {
        guard #available(iOS 27.0, *) else { return }
        let result = try await JotSplitEvaluation().run()
        #expect(!result.errors.hasFailures)
        #expect(result.aggregateValue(.mean(of: Metric("pieces"))) >= 0.8)
    }
}
#endif

// MARK: AppIntentsTesting (iOS 27): Siri's view of the app

#if canImport(AppIntentsTesting)
@Suite(.serialized) struct SiriIntentTests {
    @available(iOS 27.0, *)
    private var definitions: IntentDefinitions {
        IntentDefinitions(bundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    }

    @Test func jotSavesANoteAndSiriCanFindIt() async throws {
        guard #available(iOS 27.0, *) else { return }
        let line = "pasta maker for the kitchen \(UUID().uuidString.prefix(6))"
        let result = try await definitions.intents["JotIntent"].makeIntent(text: line).run()
        let said: String = try result.value
        #expect(said == "Saved it as a note.")

        let notes = try await definitions.entities["NoteEntity"].entities(matching: "pasta maker")
        #expect(!notes.isEmpty)
    }

    @Test func occasionsAnswerQueries() async throws {
        guard #available(iOS 27.0, *) else { return }
        // A fresh Simulator has no contacts, so this checks the query runs, not what it finds.
        _ = try await definitions.entities["OccasionEntity"].suggestedEntities()
    }
}
#endif
