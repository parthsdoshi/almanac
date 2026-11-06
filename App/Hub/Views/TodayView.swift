import SwiftUI

/// The hub's front page: the day in two sentences, who to reach out to,
/// the next workout and today's reminders.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(HubStore.self) private var hub
    @Environment(WorkoutUI.self) private var workouts
    @Environment(\.scenePhase) private var scenePhase

    @State private var capturing = false
    @State private var addingLine: String?
    @State private var rundown: String?
    @State private var reminders: [RemindersService.Item] = []
    @State private var events: [RemindersService.Event] = []
    @State private var askedReminders = RemindersService.hasReminderAccess || !RemindersService.reminderAccessUndecided

    private var todays: [UpcomingItem] { model.upcoming.filter { $0.daysUntil == 0 } }
    private var soon: [UpcomingItem] { Array(model.upcoming.filter { (1...7).contains($0.daysUntil) }.prefix(3)) }
    private var log: WorkoutLog { hub.state.workouts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ScreenHeader(
                        title: "Today",
                        eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).replacingOccurrences(of: ",", with: " ·"))

                    CaptureBar { capturing = true }

                    rundownCard

                    ForEach(todays) { item in
                        TodayCard(
                            item: item,
                            onOpen: { model.show(occasionID: item.occasion.id) },
                            onMessage: { model.beginMessage(item.occasion) },
                            onCall: { model.beginCall(item.occasion) })
                    }

                    workoutCard

                    remindersSection

                    if !soon.isEmpty {
                        SectionTitle(title: "Coming up").padding(.top, Theme.Spacing.xs)
                        RuledCard {
                            ForEach(Array(soon.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { HairRule() }
                                Button { model.show(occasionID: item.occasion.id) } label: {
                                    OccasionRow(item: item).padding(.horizontal, 14).padding(.vertical, 4).contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.paper)
            .refreshable { await refresh(rewrite: true) }
            .tabScreen("Today")
            .sheet(isPresented: $capturing) {
                CaptureSheet { line in addingLine = line }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: Binding(get: { addingLine.map(LineID.init) }, set: { addingLine = $0?.id })) { line in
                AddOccasionView(initialText: line.id)
            }
            .onChange(of: capturing) { _, open in if !open { Task { await refresh(rewrite: false) } } }
            .task { await refresh(rewrite: true) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh(rewrite: false) } } }
        }
    }

    private struct LineID: Identifiable { let id: String }

    // MARK: Rundown

    @ViewBuilder
    private var rundownCard: some View {
        if let rundown, !rundown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Your day")
                Text(rundown)
                    .font(Theme.Typography.display(19, .italic, relativeTo: .title3))
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.l)
            .background(Theme.Colors.sunk, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private func facts() -> DayFacts {
        var f = DayFacts()
        f.occasionsToday = todays.map { item in
            let who = item.occasion.firstNames.isEmpty ? item.occasion.fullNames : Names.join(item.occasion.firstNames)
            switch (item.occasion.kind, item.years) {
            case (.birthday, let y?): return "\(who) turns \(y)"
            case (.birthday, nil): return "It's \(who)'s birthday"
            case (.anniversary, let y?): return "\(who): \(y) years married"
            case (.anniversary, nil): return "\(who)'s anniversary"
            }
        }
        f.dayKind = WorkoutPlan.dayKind(.now)
        let next = WorkoutEngine.def(WorkoutEngine.suggestedNext(log), log)
        f.nextWorkout = "Workout \(next.id.rawValue) (\(next.title.lowercased()))"
        f.liftedToday = WorkoutEngine.didLiftToday(log)
        f.eventCount = events.count
        if let e = events.first { f.firstEvent = "\(e.title) at \(e.start.formatted(date: .omitted, time: .shortened))" }
        let open = reminders.filter { !$0.done }
        f.reminderCount = open.count
        if let r = open.first {
            f.firstReminder = r.title
            if r.dueHasTime, let due = r.due { f.firstReminder! += " at \(due.formatted(date: .omitted, time: .shortened))" }
        }
        return f
    }

    private func refresh(rewrite: Bool) async {
        reminders = await RemindersService.shared.today()
        events = RemindersService.shared.eventsToday()
        rundown = DayRundown.rundown(facts())
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutCard: some View {
        let def = WorkoutEngine.def(WorkoutEngine.suggestedNext(log), log)
        let lifted = WorkoutEngine.didLiftToday(log)
        HStack(spacing: 14) {
            Text(lifted ? "✓" : def.id.rawValue)
                .font(Theme.Typography.display(28, .black))
                .foregroundStyle(Theme.Colors.goldOnInk)
                .frame(width: 44, height: 50)
                .background(Theme.Colors.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: lifted ? "Lifted today" : "\(WorkoutPlan.dayKind(.now)) · up next")
                Text(lifted ? lastSummary : def.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(2)
                Text("\(def.blocks.count) blocks · about \(def.estimatedMinutes) min · \(streakText)")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            Spacer(minLength: 0)
            if !lifted {
                Button(workouts.resumable != nil ? "Resume" : "Start") {
                    if workouts.resumable != nil { workouts.resume() } else { workouts.start(def.id) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.paper)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.Colors.ink, in: Capsule())
            }
        }
        .padding(Theme.Spacing.l)
        .paperCard()
    }

    private var streakText: String {
        let s = WorkoutEngine.weekStreak(log)
        return s == 0 ? "no streak yet" : "\(s) week streak"
    }

    private var lastSummary: String {
        guard let s = log.history.last else { return "" }
        return "Workout \(s.workout.rawValue) in \(max(1, s.durationSec / 60)) min, \(s.sets.count) sets"
    }

    // MARK: Reminders

    @ViewBuilder
    private var remindersSection: some View {
        if RemindersService.hasReminderAccess {
            if !reminders.isEmpty {
                SectionTitle(title: "Reminders").padding(.top, Theme.Spacing.xs)
                RuledCard {
                    ForEach(Array(reminders.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { HairRule() }
                        TodoRow(title: r.title, detail: detail(r), done: r.done) {
                            RemindersService.shared.setDone(r.id, !r.done)
                            Task { await refresh(rewrite: false) }
                        }
                    }
                }
            }
        } else if !askedReminders {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("See today's reminders here")
                    .font(Theme.Typography.rowTitle).foregroundStyle(Theme.Colors.ink)
                Text("To-dos you jot go to Apple Reminders, so they sync and Siri sees them.")
                    .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
                Button("Connect Reminders") {
                    Task {
                        _ = await RemindersService.shared.requestReminderAccess()
                        askedReminders = true
                        await refresh(rewrite: false)
                    }
                }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
            }
            .padding(Theme.Spacing.l)
            .paperCard()
        }
    }

    private func detail(_ r: RemindersService.Item) -> String? {
        if r.done { return "Done" }
        guard let due = r.due else { return r.listTitle.isEmpty ? nil : r.listTitle }
        let cal = Calendar.current
        if due < cal.startOfDay(for: .now) { return "Overdue · " + due.formatted(.dateTime.month(.abbreviated).day()) }
        return r.dueHasTime ? due.formatted(date: .omitted, time: .shortened) : "Today"
    }
}
