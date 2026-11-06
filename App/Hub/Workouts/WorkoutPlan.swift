import Foundation

// The A/B lifting plan, ported from the workout tracker on Parth's site
// (src/components/workout/plan.ts). Ids match the web app so its backup
// file imports straight in.

final class Exercise: Identifiable, Hashable, @unchecked Sendable {
    enum PerSide: String { case leg, arm, side }

    let id: String
    let name: String
    let repsMin: Int
    let repsMax: Int
    /// Sets are measured in seconds instead of reps.
    let timed: Bool
    let perSide: PerSide?
    let muscles: [String]
    /// Pounds added or removed per tap.
    let weightStep: Double
    let defaultWeight: Double
    let weightNote: String?
    let note: String?
    /// Shown once the working weight reaches `atWeight`.
    let capNote: (atWeight: Double, note: String)?
    /// Once every set hits the top of the rep range at `atWeight` or more, the slot goes to `to`.
    let graduation: (atWeight: Double, to: Exercise)?

    init(id: String, name: String, repsMin: Int, repsMax: Int, timed: Bool = false, perSide: PerSide? = nil,
         muscles: [String], weightStep: Double, defaultWeight: Double, weightNote: String? = nil,
         note: String? = nil, capNote: (atWeight: Double, note: String)? = nil,
         graduation: (atWeight: Double, to: Exercise)? = nil) {
        self.id = id
        self.name = name
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.timed = timed
        self.perSide = perSide
        self.muscles = muscles
        self.weightStep = weightStep
        self.defaultWeight = defaultWeight
        self.weightNote = weightNote
        self.note = note
        self.capNote = capNote
        self.graduation = graduation
    }

    static func == (a: Exercise, b: Exercise) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// "8–10 reps", "8 / leg", "30–40 sec".
    var repsLabel: String {
        let range = repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)"
        if timed { return "\(range) sec" }
        if let side = perSide { return "\(range) / \(side.rawValue)" }
        return "\(range) reps"
    }

    var unit: String { timed ? "sec" : "reps" }
}

enum WorkoutBlock {
    case single(label: String, sets: Int, restSec: Int, exercise: Exercise)
    /// `setsB` is the second exercise's set count when the pair is uneven.
    case superset(label: String, sets: Int, setsB: Int?, restSec: Int, a: Exercise, b: Exercise)

    var label: String {
        switch self {
        case .single(let l, _, _, _), .superset(let l, _, _, _, _, _): l
        }
    }

    var restSec: Int {
        switch self {
        case .single(_, _, let r, _), .superset(_, _, _, let r, _, _): r
        }
    }

    var exercises: [Exercise] {
        switch self {
        case .single(_, _, _, let e): [e]
        case .superset(_, _, _, _, let a, let b): [a, b]
        }
    }

    func plannedSets(for exerciseID: String) -> Int {
        switch self {
        case .single(_, let sets, _, _): sets
        case .superset(_, let sets, let setsB, _, _, let b): exerciseID == b.id ? (setsB ?? sets) : sets
        }
    }

    func replacing(_ map: (Exercise) -> Exercise) -> WorkoutBlock {
        switch self {
        case .single(let l, let s, let r, let e): .single(label: l, sets: s, restSec: r, exercise: map(e))
        case .superset(let l, let s, let sb, let r, let a, let b): .superset(label: l, sets: s, setsB: sb, restSec: r, a: map(a), b: map(b))
        }
    }
}

enum WorkoutID: String, Codable, CaseIterable, Sendable {
    case a = "A", b = "B"
    var other: WorkoutID { self == .a ? .b : .a }
}

struct WorkoutDef: Identifiable {
    let id: WorkoutID
    let title: String
    let blocks: [WorkoutBlock]

    var muscles: [String] {
        var out: [String] = []
        for ex in blocks.flatMap(\.exercises) {
            for m in ex.muscles where !out.contains(m) { out.append(m) }
        }
        return out
    }

    var setCount: Int {
        blocks.reduce(0) { sum, b in sum + b.exercises.reduce(0) { $0 + b.plannedSets(for: $1.id) } }
    }

    /// Rough minutes: 45 seconds a set plus the rests.
    var estimatedMinutes: Int {
        let steps = WorkoutPlan.steps(for: self)
        let seconds = steps.count * 45 + steps.reduce(0) { $0 + $1.restAfterSec }
        return Int((Double(seconds) / 60).rounded())
    }
}

/// One set on the floor, in order.
struct SetStep: Identifiable, Hashable {
    let id: String
    let blockLabel: String
    let exercise: Exercise
    let setNumber: Int
    let totalSets: Int
    /// 0 means a superset hand-off: go straight to the next step.
    let restAfterSec: Int
    /// First half of a superset pair; the partner comes right after.
    let partnerName: String?
    /// Second half of a superset pair, reached with no rest.
    let pairSecond: Bool
}

enum WorkoutPlan {
    static let bulgarianSplitSquat = Exercise(
        id: "bulgarian-split-squat", name: "Bulgarian split squat", repsMin: 8, repsMax: 10, perSide: .leg,
        muscles: ["Quads", "Glutes", "Hamstrings", "Core"], weightStep: 5, defaultWeight: 20,
        weightNote: "per dumbbell",
        note: "Rear foot on the bench. All reps on one leg, then switch. Drop straight down, front knee tracking over the foot.")

    static let workoutA = WorkoutDef(id: .a, title: "Squat, bench, row, hinge", blocks: [
        .single(label: "1", sets: 3, restSec: 120, exercise: Exercise(
            id: "goblet-squat", name: "Goblet squat", repsMin: 8, repsMax: 10,
            muscles: ["Quads", "Glutes", "Core"], weightStep: 5, defaultWeight: 0,
            weightNote: "pick a weight that leaves 2 reps in the tank",
            graduation: (50, bulgarianSplitSquat))),
        .superset(label: "2", sets: 3, setsB: nil, restSec: 90,
            a: Exercise(
                id: "db-bench", name: "DB bench press", repsMin: 6, repsMax: 10,
                muscles: ["Chest", "Front delts", "Triceps"], weightStep: 5, defaultWeight: 45,
                weightNote: "per dumbbell",
                note: "Wrist stacked over the elbow, knuckles to the ceiling, DB in the heel of the palm.",
                capNote: (50, "At 50s for 10: switch to incline or add a 2-second pause at the bottom and climb again.")),
            b: Exercise(
                id: "db-row", name: "Chest-supported DB row", repsMin: 8, repsMax: 12,
                muscles: ["Lats", "Upper back", "Rear delts", "Biceps"], weightStep: 5, defaultWeight: 30,
                weightNote: "per dumbbell",
                note: "Chest pinned, one-second squeeze at the top. Pull with the elbow, don’t death-grip. Goal: match or beat your bench.")),
        .superset(label: "3", sets: 2, setsB: nil, restSec: 75,
            a: Exercise(
                id: "db-rdl", name: "DB Romanian deadlift", repsMin: 8, repsMax: 10,
                muscles: ["Hamstrings", "Glutes", "Lower back"], weightStep: 5, defaultWeight: 35,
                weightNote: "per dumbbell"),
            b: Exercise(
                id: "lateral-raise", name: "Lateral raise", repsMin: 12, repsMax: 15,
                muscles: ["Side delts"], weightStep: 5, defaultWeight: 10, weightNote: "per dumbbell")),
        .single(label: "4", sets: 2, restSec: 60, exercise: Exercise(
            id: "pallof-press", name: "Cable Pallof press", repsMin: 10, repsMax: 10, perSide: .side,
            muscles: ["Core"], weightStep: 2.5, defaultWeight: 0,
            note: "If time allows — first cut when running over.")),
    ])

    static let workoutB = WorkoutDef(id: .b, title: "Lunge, overhead press, pulldown", blocks: [
        .single(label: "1", sets: 3, restSec: 120, exercise: Exercise(
            id: "reverse-lunge", name: "DB reverse lunge", repsMin: 8, repsMax: 8, perSide: .leg,
            muscles: ["Quads", "Glutes", "Hamstrings", "Core"], weightStep: 5, defaultWeight: 20,
            weightNote: "per dumbbell",
            note: "All 8 on one leg, then switch — alternating is easier and you’ll go too light.")),
        .superset(label: "2", sets: 3, setsB: nil, restSec: 90,
            a: Exercise(
                id: "db-shoulder-press", name: "DB shoulder press", repsMin: 6, repsMax: 10,
                muscles: ["Front delts", "Side delts", "Triceps"], weightStep: 5, defaultWeight: 20,
                weightNote: "per dumbbell",
                note: "Wrist stacked over the elbow, knuckles to the ceiling, DB in the heel of the palm."),
            b: Exercise(
                id: "sa-lat-pulldown", name: "Half-kneeling single-arm lat pulldown", repsMin: 8, repsMax: 12, perSide: .arm,
                muscles: ["Lats", "Biceps", "Core"], weightStep: 2.5, defaultWeight: 0,
                weightNote: "your pull-up substitute",
                note: "Hands are hooks — pull with the elbow, don’t death-grip.")),
        .superset(label: "3", sets: 2, setsB: nil, restSec: 75,
            a: Exercise(
                id: "cable-pull-through", name: "Cable pull-through", repsMin: 10, repsMax: 12,
                muscles: ["Glutes", "Hamstrings", "Lower back"], weightStep: 2.5, defaultWeight: 0),
            b: Exercise(
                id: "face-pull", name: "Face pulls", repsMin: 15, repsMax: 15,
                muscles: ["Rear delts", "Upper back"], weightStep: 2.5, defaultWeight: 0)),
        .superset(label: "4", sets: 2, setsB: nil, restSec: 60,
            a: Exercise(
                id: "incline-hammer-curl", name: "Incline hammer curl", repsMin: 10, repsMax: 12,
                muscles: ["Biceps", "Forearms"], weightStep: 5, defaultWeight: 15,
                weightNote: "per dumbbell · bench at 45°",
                note: "Back on the pad, arms hanging, palms in. Elbows behind the torso, full straighten, slow negative. Bench taken? Back flat against a wall. Deliberately light — earn it back with clean reps."),
            b: Exercise(
                id: "tricep-pushdown", name: "Tricep pushdown", repsMin: 10, repsMax: 12,
                muscles: ["Triceps"], weightStep: 2.5, defaultWeight: 28)),
        .superset(label: "5", sets: 3, setsB: 2, restSec: 60,
            a: Exercise(
                id: "farmers-carry", name: "Farmer's carry", repsMin: 30, repsMax: 40, timed: true,
                muscles: ["Grip", "Forearms", "Upper back", "Core"], weightStep: 5, defaultWeight: 50,
                weightNote: "per hand",
                note: "The wrist fix, part one. Stand tall, don’t let the shoulders sag."),
            b: Exercise(
                id: "wrist-curl", name: "Wrist curl + reverse", repsMin: 15, repsMax: 15,
                muscles: ["Forearms"], weightStep: 5, defaultWeight: 10,
                note: "15 each way. Already at 35 min? Do the carries, skip these.")),
    ])

    static let workouts: [WorkoutDef] = [workoutA, workoutB]

    static func steps(for w: WorkoutDef) -> [SetStep] {
        var steps: [SetStep] = []
        for (bi, block) in w.blocks.enumerated() {
            switch block {
            case .single(let label, let sets, let rest, let ex):
                for s in 1...max(sets, 1) {
                    steps.append(SetStep(id: "\(bi)-\(ex.id)-\(s)", blockLabel: label, exercise: ex, setNumber: s,
                                         totalSets: sets, restAfterSec: rest, partnerName: nil, pairSecond: false))
                }
            case .superset(let label, let sets, let setsB, let rest, let a, let b):
                let bSets = setsB ?? sets
                for s in 1...max(sets, bSets, 1) {
                    let hasA = s <= sets, hasB = s <= bSets
                    if hasA {
                        steps.append(SetStep(id: "\(bi)-\(a.id)-\(s)", blockLabel: "\(label)a", exercise: a, setNumber: s,
                                             totalSets: sets, restAfterSec: hasB ? 0 : rest,
                                             partnerName: hasB ? b.name : nil, pairSecond: false))
                    }
                    if hasB {
                        steps.append(SetStep(id: "\(bi)-\(b.id)-\(s)", blockLabel: "\(label)b", exercise: b, setNumber: s,
                                             totalSets: bSets, restAfterSec: rest, partnerName: nil, pairSecond: hasA))
                    }
                }
            }
        }
        return steps
    }

    /// Applies graduations (base exercise id -> successor id) to a workout.
    static func resolve(_ def: WorkoutDef, overrides: [String: String]) -> WorkoutDef {
        WorkoutDef(id: def.id, title: def.title, blocks: def.blocks.map { block in
            block.replacing { ex in
                if let to = ex.graduation?.to, overrides[ex.id] == to.id { return to }
                return ex
            }
        })
    }

    /// Every exercise the plan can put on the floor, graduation targets included.
    static var allExercises: [Exercise] {
        var out: [Exercise] = []
        for ex in workouts.flatMap({ $0.blocks.flatMap(\.exercises) }) {
            out.append(ex)
            if let to = ex.graduation?.to { out.append(to) }
        }
        return out
    }

    static func exercise(id: String) -> Exercise? { allExercises.first { $0.id == id } }

    static func formatTime(_ totalSec: Int) -> String {
        let sec = max(0, totalSec)
        return "\(sec / 60):" + String(format: "%02d", sec % 60)
    }

    /// The web app's day labels: Tue and Thu are runs, weekends rest.
    static func dayKind(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1, 7: "rest day"
        case 3, 5: "run day"
        default: "lift day"
        }
    }
}
