import Foundation

/// The tracker's rules, kept free of UI so they can be tested.
enum WorkoutEngine {
    /// A follows B and B follows A, like the web app.
    static func suggestedNext(_ log: WorkoutLog) -> WorkoutID {
        log.history.last?.workout == .a ? .b : .a
    }

    static func resolved(_ log: WorkoutLog) -> [WorkoutDef] {
        WorkoutPlan.workouts.map { WorkoutPlan.resolve($0, overrides: log.overrides) }
    }

    static func def(_ id: WorkoutID, _ log: WorkoutLog) -> WorkoutDef {
        resolved(log).first { $0.id == id } ?? WorkoutPlan.workoutA
    }

    struct Perf: Equatable {
        let date: Date
        let weight: Double
        let reps: [Int]
    }

    static func lastPerf(_ exerciseID: String, in log: WorkoutLog) -> Perf? {
        for s in log.history.reversed() {
            let done = s.sets.filter { $0.exerciseId == exerciseID }
            if let last = done.last { return Perf(date: s.startDate, weight: last.weight, reps: done.map(\.reps)) }
        }
        return nil
    }

    static func defaultReps(_ ex: Exercise, setNumber: Int, in log: WorkoutLog) -> Int {
        for s in log.history.reversed() {
            if let m = s.sets.first(where: { $0.exerciseId == ex.id && $0.setNumber == setNumber }) { return m.reps }
        }
        return ex.repsMin
    }

    static func lastNote(_ exerciseID: String, in log: WorkoutLog) -> String? {
        for s in log.history.reversed() {
            if let n = s.exerciseNotes?[exerciseID], !n.isEmpty { return n }
        }
        return nil
    }

    /// Weeks in a row, ending this week or last, with at least one session.
    static func weekStreak(_ log: WorkoutLog, now: Date = .now, calendar: Calendar = .current) -> Int {
        var cal = calendar
        cal.firstWeekday = 2
        func weekStart(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d }
        let weeks = Set(log.history.map { weekStart($0.startDate) })
        var cursor = weekStart(now)
        if !weeks.contains(cursor) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor), weeks.contains(prev) else { return 0 }
            cursor = prev
        }
        var count = 0
        while weeks.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    static func sessionsThisMonth(_ log: WorkoutLog, now: Date = .now, calendar: Calendar = .current) -> Int {
        log.history.filter { calendar.isDate($0.startDate, equalTo: now, toGranularity: .month) }.count
    }

    static func didLiftToday(_ log: WorkoutLog, now: Date = .now, calendar: Calendar = .current) -> Bool {
        log.history.contains { calendar.isDate($0.startDate, inSameDayAs: now) }
    }

    struct Graduation: Hashable {
        let from: Exercise
        let to: Exercise
    }

    /// Saves a finished session and works out graduations.
    static func finish(_ session: WorkoutSession, def: WorkoutDef, log: inout WorkoutLog) -> [Graduation] {
        guard !session.sets.isEmpty else { return [] }
        log.history.append(session)
        var earned: [Graduation] = []
        for block in def.blocks {
            for ex in block.exercises {
                guard let g = ex.graduation, log.overrides[ex.id] == nil else { continue }
                let logged = session.sets.filter { $0.exerciseId == ex.id }
                if logged.count >= block.plannedSets(for: ex.id),
                   logged.allSatisfy({ $0.reps >= ex.repsMax && $0.weight >= g.atWeight }) {
                    log.overrides[ex.id] = g.to.id
                    if log.weights[g.to.id] == nil { log.weights[g.to.id] = g.to.defaultWeight }
                    earned.append(Graduation(from: ex, to: g.to))
                }
            }
        }
        return earned
    }

    struct SummaryRow: Identifiable {
        var id: String { exercise.id }
        let exercise: Exercise
        let logged: [LoggedSet]
        let hitTop: Bool
        let graduatedTo: Exercise?
    }

    static func summary(_ session: WorkoutSession, def: WorkoutDef, graduations: [Graduation]) -> [SummaryRow] {
        def.blocks.flatMap { block in
            block.exercises.compactMap { ex -> SummaryRow? in
                let logged = session.sets.filter { $0.exerciseId == ex.id }
                guard !logged.isEmpty else { return nil }
                let top = logged.count >= block.plannedSets(for: ex.id) && logged.allSatisfy { $0.reps >= ex.repsMax }
                return SummaryRow(exercise: ex, logged: logged, hitTop: top,
                                  graduatedTo: graduations.first { $0.from.id == ex.id }?.to)
            }
        }
    }

    static func roundWeight(_ x: Double) -> Double { (x * 2).rounded() / 2 }

    static func formatWeight(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }

    // MARK: Backup import

    enum ImportError: LocalizedError {
        case unreadable, notABackup
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read that file."
            case .notABackup: "That isn't a workout backup file."
            }
        }
    }

    /// Reads the web tracker's "Export backup" file. Skips anything malformed
    /// rather than failing the whole import, like the web app does.
    static func importBackup(_ data: Data) throws -> WorkoutLog {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ImportError.unreadable
        }
        var log = WorkoutLog()
        for raw in root["history"] as? [[String: Any]] ?? [] {
            guard let date = raw["date"] as? String,
                  let w = (raw["workout"] as? String).flatMap(WorkoutID.init(rawValue:)),
                  let duration = number(raw["durationSec"]),
                  let rawSets = raw["sets"] as? [[String: Any]] else { continue }
            let sets = rawSets.compactMap { s -> LoggedSet? in
                guard let id = s["exerciseId"] as? String, let name = s["name"] as? String,
                      let label = s["blockLabel"] as? String, let n = number(s["setNumber"]),
                      let weight = number(s["weight"]), let reps = number(s["reps"]) else { return nil }
                return LoggedSet(exerciseId: id, name: name, blockLabel: label, setNumber: Int(n), weight: weight, reps: Int(reps))
            }
            let notes = (raw["exerciseNotes"] as? [String: Any])?.compactMapValues { v -> String? in
                guard let s = v as? String, !s.isEmpty else { return nil }
                return s
            }
            let note = (raw["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            log.history.append(WorkoutSession(date: date, workout: w, durationSec: Int(duration), sets: sets,
                                              note: note, exerciseNotes: (notes?.isEmpty ?? true) ? nil : notes))
        }
        for (k, v) in root["weights"] as? [String: Any] ?? [:] {
            if let n = number(v), n.isFinite { log.weights[k] = max(0, n) }
        }
        guard !log.history.isEmpty || !log.weights.isEmpty else { throw ImportError.notABackup }
        log.history.sort { $0.date < $1.date }
        for ex in WorkoutPlan.allExercises where log.weights[ex.id] == nil { log.weights[ex.id] = ex.defaultWeight }
        let known = Set(WorkoutPlan.allExercises.compactMap { ex in ex.graduation.map { "\(ex.id)>\($0.to.id)" } })
        for (k, v) in root["overrides"] as? [String: Any] ?? [:] {
            if let to = v as? String, known.contains("\(k)>\(to)") { log.overrides[k] = to }
        }
        var byDate: [String: Double] = [:]
        for raw in root["bodyweight"] as? [[String: Any]] ?? [] {
            if let d = raw["date"] as? String, d.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
               let lb = number(raw["lb"]), lb.isFinite, lb > 0 {
                byDate[d] = (lb * 10).rounded() / 10
            }
        }
        log.bodyweight = byDate.map { BodyweightEntry(date: $0.key, lb: $0.value) }.sorted { $0.date < $1.date }
        return log
    }

    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
}
