import Foundation
import Observation
import UIKit
import UserNotifications

/// A workout in progress: which set you're on, the rest timer and what you logged.
@MainActor
@Observable
final class WorkoutSessionModel {
    enum Phase: String, Codable { case warmup, work, rest }

    private(set) var def: WorkoutDef
    private(set) var steps: [SetStep]
    private(set) var stepIndex = 0
    private(set) var phase: Phase = .warmup
    private(set) var sets: [LoggedSet] = []
    var exerciseNotes: [String: String] = [:]
    let startedAt: Date
    private(set) var restEndsAt: Date?
    private(set) var restTotal = 0
    var reps = 0

    @ObservationIgnored private let hub: HubStore

    init(def: WorkoutDef, hub: HubStore = .shared) {
        self.def = def
        self.hub = hub
        steps = WorkoutPlan.steps(for: def)
        startedAt = .now
        UIApplication.shared.isIdleTimerDisabled = true
        save()
    }

    var step: SetStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var nextStep: SetStep? { steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1] : nil }
    var progress: Double { steps.isEmpty ? 0 : Double(stepIndex) / Double(steps.count) }

    func weight(for ex: Exercise) -> Double { hub.state.workouts.weight(for: ex) }

    func adjustWeight(_ ex: Exercise, by dir: Double) {
        let w = WorkoutEngine.roundWeight(max(0, weight(for: ex) + dir * ex.weightStep))
        hub.update { $0.workouts.weights[ex.id] = w }
    }

    var nextUpText: String {
        guard let s = step else { return "" }
        guard let next = nextStep else { return "Last set of the day. Finish strong." }
        if s.restAfterSec == 0 { return "Superset: \(next.exercise.name) right after, no rest" }
        return "Then rest \(WorkoutPlan.formatTime(s.restAfterSec)), then \(next.exercise.name), set \(next.setNumber) of \(next.totalSets)"
    }

    func startFirstSet() {
        phase = .work
        prepReps()
        save()
    }

    /// Logs the set (or skips it) and moves on.
    /// Returns true when that was the last set.
    @discardableResult
    func advance(log: Bool) -> Bool {
        guard let s = step else { return true }
        if log {
            sets.append(LoggedSet(exerciseId: s.exercise.id, name: s.exercise.name, blockLabel: s.blockLabel,
                                  setNumber: s.setNumber, weight: weight(for: s.exercise), reps: reps))
        }
        if stepIndex >= steps.count - 1 { return true }
        stepIndex += 1
        if s.restAfterSec == 0 {
            phase = .work
            prepReps()
        } else {
            restTotal = s.restAfterSec
            restEndsAt = Date.now.addingTimeInterval(TimeInterval(s.restAfterSec))
            phase = .rest
            scheduleRestAlert()
        }
        save()
        return false
    }

    func endRest() {
        phase = .work
        restEndsAt = nil
        cancelRestAlert()
        prepReps()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        save()
    }

    func adjustRest(by seconds: Int) {
        guard let end = restEndsAt else { return }
        restEndsAt = max(Date.now, end.addingTimeInterval(TimeInterval(seconds)))
        restTotal = max(restTotal, Int(restEndsAt!.timeIntervalSinceNow.rounded()))
        scheduleRestAlert()
        save()
    }

    private func prepReps() {
        guard let s = step else { return }
        reps = WorkoutEngine.defaultReps(s.exercise, setNumber: s.setNumber, in: hub.state.workouts)
    }

    /// Saves the session to the log. Returns what the summary needs.
    func finish() -> (session: WorkoutSession, graduations: [WorkoutEngine.Graduation])? {
        cancelRestAlert()
        WorkoutActivity.endAll()
        UIApplication.shared.isIdleTimerDisabled = false
        Self.clearSaved()
        let notes = exerciseNotes.compactMapValues { v -> String? in
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let session = WorkoutSession(
            date: WorkoutDates.string(startedAt), workout: def.id,
            durationSec: max(0, Int(Date.now.timeIntervalSince(startedAt))), sets: sets,
            note: nil, exerciseNotes: notes.isEmpty ? nil : notes)
        guard !sets.isEmpty else { return nil }
        var grads: [WorkoutEngine.Graduation] = []
        hub.update { grads = WorkoutEngine.finish(session, def: def, log: &$0.workouts) }
        return (session, grads)
    }

    func discard() {
        cancelRestAlert()
        WorkoutActivity.endAll()
        UIApplication.shared.isIdleTimerDisabled = false
        Self.clearSaved()
    }

    // MARK: Rest alert when the phone is locked

    private static let restAlertID = "workout-rest"

    private func scheduleRestAlert() {
        guard let end = restEndsAt, end > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = step.map { "\($0.exercise.name), set \($0.setNumber) of \($0.totalSets)" } ?? "Next set"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.restAlertID, content: content, trigger: trigger))
    }

    private func cancelRestAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.restAlertID])
    }

    // MARK: Picking up after the app was closed mid-workout

    private struct Snapshot: Codable {
        var workout: WorkoutID
        var stepIndex: Int
        var phase: Phase
        var sets: [LoggedSet]
        var exerciseNotes: [String: String]
        var startedAt: Date
        var restEndsAt: Date?
        var restTotal: Int
    }

    private static let savedKey = "workout.active"

    private func save() {
        let snap = Snapshot(workout: def.id, stepIndex: stepIndex, phase: phase, sets: sets, exerciseNotes: exerciseNotes,
                            startedAt: startedAt, restEndsAt: restEndsAt, restTotal: restTotal)
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: Self.savedKey) }
        WorkoutActivity.sync(self)
    }

    static func clearSaved() { UserDefaults.standard.removeObject(forKey: savedKey) }

    /// A workout left unfinished in the last 12 hours.
    static var resumable: (workout: WorkoutID, startedAt: Date, setsLogged: Int)? {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.startedAt.timeIntervalSinceNow > -12 * 3600 else { return nil }
        return (snap.workout, snap.startedAt, snap.sets.count)
    }

    static func resume(hub: HubStore = .shared) -> WorkoutSessionModel? {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        let def = WorkoutEngine.def(snap.workout, hub.state.workouts)
        let m = WorkoutSessionModel(def: def, hub: hub, startedAt: snap.startedAt)
        m.stepIndex = min(snap.stepIndex, max(0, m.steps.count - 1))
        m.phase = snap.phase
        m.sets = snap.sets
        m.exerciseNotes = snap.exerciseNotes
        m.restEndsAt = snap.restEndsAt
        m.restTotal = snap.restTotal
        if m.phase == .rest, (m.restEndsAt ?? .distantPast) <= .now { m.phase = .work; m.restEndsAt = nil }
        if m.phase != .rest { m.prepReps() }
        m.save()
        return m
    }

    private init(def: WorkoutDef, hub: HubStore, startedAt: Date) {
        self.def = def
        self.hub = hub
        steps = WorkoutPlan.steps(for: def)
        self.startedAt = startedAt
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
