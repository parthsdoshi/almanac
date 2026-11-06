import ActivityKit
import Foundation

/// The workout Live Activity's data. Compiled into both the app and the widget
/// extension. Only the app starts and updates it (no push), so dates are fine here.
struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case warmup, work, rest }

        var phase: Phase
        /// During a set, the exercise you're on. While resting, the one that's next.
        var exercise: String
        /// e.g. "2a".
        var blockLabel: String
        var setNumber: Int
        var totalSets: Int
        /// e.g. "35 lb · aim for 6–10 reps".
        var detail: String
        /// Sets logged or skipped so far, out of `stepCount`.
        var stepsDone: Int
        var stepCount: Int
        var restStartedAt: Date?
        var restEndsAt: Date?
    }

    /// "A" or "B".
    var workout: String
    /// e.g. "Lunge, overhead press, pulldown".
    var title: String
    var startedAt: Date
}

extension WorkoutAttributes.ContentState {
    var setLine: String { "\(blockLabel) · Set \(setNumber) of \(totalSets)" }
    var progress: Double { stepCount > 0 ? min(1, Double(stepsDone) / Double(stepCount)) : 0 }
}
