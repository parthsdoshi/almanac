import Foundation
import Testing
@testable import Occasions

@Suite struct WorkoutPlanTests {
    @Test func stepsInterleaveSupersets() {
        let steps = WorkoutPlan.steps(for: WorkoutPlan.workoutA)
        // 3 goblet + 3x2 bench/row + 2x2 rdl/raise + 2 pallof
        #expect(steps.count == 3 + 6 + 4 + 2)
        #expect(steps[3].exercise.id == "db-bench")
        #expect(steps[3].restAfterSec == 0)
        #expect(steps[3].partnerName == "Chest-supported DB row")
        #expect(steps[4].exercise.id == "db-row")
        #expect(steps[4].pairSecond)
        #expect(steps[4].restAfterSec == 90)
    }

    @Test func unevenSupersetRestsAfterTheLoneSet() {
        let steps = WorkoutPlan.steps(for: WorkoutPlan.workoutB)
        let carries = steps.filter { $0.blockLabel.hasPrefix("5") }
        #expect(carries.map(\.exercise.id) == ["farmers-carry", "wrist-curl", "farmers-carry", "wrist-curl", "farmers-carry"])
        #expect(carries.last?.restAfterSec == 60)
        #expect(carries.last?.partnerName == nil)
    }

    @Test func alternatesWorkouts() {
        var log = WorkoutLog()
        #expect(WorkoutEngine.suggestedNext(log) == .a)
        log.history.append(WorkoutSession(date: "2026-11-03T12:00:00.000Z", workout: .a, durationSec: 100, sets: []))
        #expect(WorkoutEngine.suggestedNext(log) == .b)
    }

    @Test func graduatesGobletSquat() {
        var log = WorkoutLog()
        let sets = (1...3).map { LoggedSet(exerciseId: "goblet-squat", name: "Goblet squat", blockLabel: "1", setNumber: $0, weight: 50, reps: 10) }
        let s = WorkoutSession(date: "2026-11-03T12:00:00.000Z", workout: .a, durationSec: 100, sets: sets)
        let grads = WorkoutEngine.finish(s, def: WorkoutPlan.workoutA, log: &log)
        #expect(grads.first?.to.id == "bulgarian-split-squat")
        #expect(log.overrides["goblet-squat"] == "bulgarian-split-squat")
        let resolved = WorkoutEngine.def(.a, log)
        #expect(resolved.blocks[0].exercises[0].id == "bulgarian-split-squat")
    }

    @Test func noGraduationBelowTheWeight() {
        var log = WorkoutLog()
        let sets = (1...3).map { LoggedSet(exerciseId: "goblet-squat", name: "Goblet squat", blockLabel: "1", setNumber: $0, weight: 45, reps: 10) }
        let s = WorkoutSession(date: "2026-11-03T12:00:00.000Z", workout: .a, durationSec: 100, sets: sets)
        #expect(WorkoutEngine.finish(s, def: WorkoutPlan.workoutA, log: &log).isEmpty)
    }

    @Test func importsWebBackup() throws {
        let json = """
        {"app":"workout-tracker","version":1,"exportedAt":"2026-11-05T01:00:00.000Z",
         "weights":{"db-bench":50,"db-row":35.5},
         "history":[{"date":"2026-11-03T22:10:00.000Z","workout":"A","durationSec":2520,
           "sets":[{"exerciseId":"db-bench","name":"DB bench press","blockLabel":"2a","setNumber":1,"weight":50,"reps":10},
                   {"exerciseId":"bad"}],
           "exerciseNotes":{"db-bench":"felt easy"},"note":"good one"},
           {"date":"x","workout":"C","durationSec":1,"sets":[]}],
         "overrides":{"goblet-squat":"bulgarian-split-squat","db-bench":"nope"},
         "bodyweight":[{"date":"2026-11-03","lb":171.04},{"date":"bad","lb":5}]}
        """
        let log = try WorkoutEngine.importBackup(Data(json.utf8))
        #expect(log.history.count == 1)
        #expect(log.history[0].sets.count == 1)
        #expect(log.history[0].exerciseNotes?["db-bench"] == "felt easy")
        #expect(log.history[0].note == "good one")
        #expect(log.weights["db-row"] == 35.5)
        #expect(log.weights["goblet-squat"] == 0)
        #expect(log.overrides == ["goblet-squat": "bulgarian-split-squat"])
        #expect(log.bodyweight == [BodyweightEntry(date: "2026-11-03", lb: 171)])
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: WorkoutEngine.ImportError.self) { try WorkoutEngine.importBackup(Data("{\"hello\":1}".utf8)) }
    }

    @Test func weekStreakCountsBack() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        var log = WorkoutLog()
        for day in [3, 28, 21] { // Nov 3, Oct 28, Oct 21
            let month = day == 3 ? 11 : 10
            let d = cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
            log.history.append(WorkoutSession(date: WorkoutDates.string(d), workout: .a, durationSec: 1, sets: []))
        }
        #expect(WorkoutEngine.weekStreak(log, now: now, calendar: cal) == 3)
    }
}

@Suite struct CaptureRuleTests {
    @Test func remindMe() {
        let g = RuleCapture.read("remind me to call the landlord tomorrow at 2pm")
        #expect(g.kind == .reminder)
        #expect(g.text.hasPrefix("Call the landlord"))
        #expect(g.due != nil)
        #expect(g.dueHasTime)
    }

    @Test func verbFirstIsAReminder() {
        #expect(RuleCapture.read("buy olive oil").kind == .reminder)
    }

    @Test func birthdayGoesToAdd() {
        #expect(RuleCapture.read("Mom's birthday is March 3").kind == .occasion)
    }

    @Test func factAboutSomeone() {
        let g = RuleCapture.read("Priya started at Stripe")
        #expect(g.kind == .person)
        #expect(g.person == "Priya")
    }

    @Test func otherwiseANote() {
        #expect(RuleCapture.read("ideas for the trip: ella train, kandy").kind == .note)
    }

    @Test func tidyFindsTodos() {
        let n = Note(title: "", body: "Tax call prep\nCheck their CPA license. The rates seem fine. Confirm share counts before Monday.")
        let t = NoteTidier.rulesTidy(n)
        #expect(t.title == "Tax call prep")
        #expect(t.todos.map(\.text).contains("Check their CPA license"))
        #expect(t.todos.contains { $0.text.hasPrefix("Confirm share counts") })
        #expect(t.todos.count == 2)
    }

    @Test func splitsASentenceOfTodos() {
        #expect(RuleCapture.split("I need to call mom, buy milk and renew my passport") == ["call mom", "buy milk", "renew my passport"])
        #expect(RuleCapture.split("email Dan, pay rent, and book flights") == ["email Dan", "pay rent", "book flights"])
        #expect(RuleCapture.split("call the bank and pay the bill") == ["call the bank", "pay the bill"])
        #expect(RuleCapture.split("buy salt and pepper") == ["buy salt and pepper"])
        #expect(RuleCapture.split("- milk\n- eggs\n- bread") == ["milk", "eggs", "bread"])
        #expect(RuleCapture.split("call mom on Friday, Nov 7").count == 1)
    }

    @Test func listLinesBecomeTodos() {
        let g = RuleCapture.todo("milk")
        #expect(g.kind == .reminder)
        #expect(g.text == "Milk")
        #expect(g.horizon == .thisWeek)
    }

    @Test func statedHorizons() {
        #expect(Horizon.stated(in: "pay the bill asap") == .today)
        #expect(Horizon.stated(in: "i know the drill") == nil)
        #expect(Horizon.stated(in: "fix the bike next week") == .nextWeek)
    }

    @Test func horizonDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 23))! }
        func ymd(_ date: Date?) -> String { date.map { let c = cal.dateComponents([.month, .day], from: $0); return "\(c.month!)/\(c.day!)" } ?? "nil" }
        let thu = day(11, 5)
        #expect(ymd(Horizon.today.date(from: thu, calendar: cal)) == "11/5")
        #expect(ymd(Horizon.thisWeek.date(from: thu, calendar: cal)) == "11/6")
        #expect(ymd(Horizon.nextWeek.date(from: thu, calendar: cal)) == "11/13")
        #expect(ymd(Horizon.thisMonth.date(from: thu, calendar: cal)) == "11/30")
        #expect(Horizon.someday.date(from: thu, calendar: cal) == nil)
        let sat = day(11, 7)
        #expect(ymd(Horizon.thisWeek.date(from: sat, calendar: cal)) == "11/8")
        #expect(ymd(Horizon.thisMonth.date(from: day(11, 28), calendar: cal)) == "11/30")
    }

    @Test func rundownSticksToFacts() {
        var f = DayFacts()
        f.dayKind = "run day"
        #expect(DayRundown.rundown(f) == "It's a run day, no lifting.")
    }
}

@Suite struct SyncItemTests {
    private func person(_ id: String, _ given: String, _ family: String) -> Person {
        Person(contactID: id, givenName: given, familyName: family, phoneNumbers: [])
    }

    @Test func roundTripsIntoAnEmptyPhone() {
        var hub = HubState()
        hub.notes = [Note(title: "Trip", body: "Ella train")]
        hub.workouts.history = [WorkoutSession(date: "2026-11-03T12:00:00.000Z", workout: .a, durationSec: 100, sets: [])]
        hub.workouts.bodyweight = [BodyweightEntry(date: "2026-11-03", lb: 171)]
        hub.workouts.weights = ["db-bench": 50]
        let items = SyncItems.items(hub: hub, app: PersistedState(), keys: SyncKeys(), unresolved: SyncUnresolved())
        #expect(items.count == 4)

        var other = HubState()
        var app = PersistedState()
        var unresolved = SyncUnresolved()
        for (_, item) in items {
            SyncItems.apply(item.kind, item.data, hub: &other, app: &app, keys: SyncKeys(), unresolved: &unresolved)
        }
        #expect(other.notes.map(\.body) == ["Ella train"])
        #expect(other.workouts.history.count == 1)
        #expect(other.workouts.bodyweight.first?.lb == 171)
        #expect(other.workouts.weights["db-bench"] == 50)
    }

    @Test func starsMatchByNameAcrossPhones() {
        let mine = Occasion(kind: .birthday, people: [person("A1", "Priya", "Patel")], date: MonthDay(month: 3, day: 3))
        var app = PersistedState()
        app.starred = [mine.id]
        let myKeys = SyncKeys.build(occasions: [mine], contacts: [])
        let prefs = SyncItems.prefs(hub: HubState(), app: app, keys: myKeys, unresolved: SyncUnresolved())
        #expect(prefs.starred == ["birthday|priya patel"])

        // Same person, different contact id on the other phone.
        let theirs = Occasion(kind: .birthday, people: [person("ZZ9", "Priya", "Patel")], date: MonthDay(month: 3, day: 3))
        var hub = HubState()
        var otherApp = PersistedState()
        var unresolved = SyncUnresolved()
        SyncItems.apply(.prefs, SyncItems.encode(prefs), hub: &hub, app: &otherApp,
                        keys: SyncKeys.build(occasions: [theirs], contacts: []), unresolved: &unresolved)
        #expect(otherApp.starred == [theirs.id])
        #expect(unresolved.starred.isEmpty)
    }

    @Test func unknownStarsWaitForContacts() {
        var prefs = SyncPrefs()
        prefs.starred = ["birthday|priya patel"]
        var hub = HubState()
        var app = PersistedState()
        var unresolved = SyncUnresolved()
        SyncItems.apply(.prefs, SyncItems.encode(prefs), hub: &hub, app: &app, keys: SyncKeys(), unresolved: &unresolved)
        #expect(app.starred.isEmpty)
        #expect(unresolved.starred == ["birthday|priya patel"])
        // Still sent back up, so the other phone doesn't lose it.
        #expect(SyncItems.prefs(hub: hub, app: app, keys: SyncKeys(), unresolved: unresolved).starred == ["birthday|priya patel"])

        let o = Occasion(kind: .birthday, people: [person("B2", "Priya", "Patel")], date: MonthDay(month: 3, day: 3))
        SyncItems.resolve(hub: &hub, app: &app, keys: SyncKeys.build(occasions: [o], contacts: []), unresolved: &unresolved)
        #expect(app.starred == [o.id])
        #expect(unresolved.starred.isEmpty)
    }

    @Test func deletionsRemoveTheThing() {
        var hub = HubState()
        let n = Note(title: "", body: "x")
        hub.notes = [n]
        SyncItems.remove("note.\(n.id.uuidString)", hub: &hub)
        #expect(hub.notes.isEmpty)
    }
}
