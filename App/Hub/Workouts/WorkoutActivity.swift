import ActivityKit
import Foundation

/// Keeps the workout Live Activity in step with the session: started with the
/// workout, updated on every set and rest, ended when it's saved or thrown away.
@MainActor
enum WorkoutActivity {
    static func sync(_ session: WorkoutSessionModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(session)
        // A rest's countdown runs by itself; mark it stale once it's over so iOS dims it.
        let content = ActivityContent(state: state, staleDate: state.restEndsAt)
        if let current = Activity<WorkoutAttributes>.activities.first(where: { $0.attributes.startedAt == session.startedAt }) {
            Task { await current.update(content) }
            return
        }
        // A different workout's activity left over (the app was closed mid-workout).
        endAll()
        let attributes = WorkoutAttributes(workout: session.def.id.rawValue, title: session.def.title, startedAt: session.startedAt)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func endAll() {
        for activity in Activity<WorkoutAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func contentState(_ session: WorkoutSessionModel) -> WorkoutAttributes.ContentState {
        let step = session.step
        let ex = step?.exercise
        var detail = ""
        if let ex {
            let w = session.weight(for: ex)
            let weight = w > 0 ? "\(WorkoutEngine.formatWeight(w)) lb · " : ""
            detail = weight + "aim for \(ex.repsLabel)"
        }
        let resting = session.phase == .rest
        let restEnds = resting ? session.restEndsAt : nil
        return WorkoutAttributes.ContentState(
            phase: WorkoutAttributes.ContentState.Phase(rawValue: session.phase.rawValue) ?? .work,
            exercise: ex?.name ?? session.def.title,
            blockLabel: step?.blockLabel ?? "",
            setNumber: step?.setNumber ?? 0,
            totalSets: step?.totalSets ?? 0,
            detail: detail,
            stepsDone: session.phase == .warmup ? 0 : session.stepIndex,
            stepCount: session.steps.count,
            restStartedAt: restEnds.map { $0.addingTimeInterval(-TimeInterval(session.restTotal)) },
            restEndsAt: restEnds)
    }
}
