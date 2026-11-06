import SwiftUI

/// Full-screen cover for a workout: the set you're on, the rest timer, then the summary.
struct WorkoutCover: View {
    @Environment(WorkoutUI.self) private var ui

    var body: some View {
        Group {
            if let active = ui.active {
                WorkoutSessionView(session: active)
            } else if let done = ui.finished {
                WorkoutSummaryView(finished: done)
            }
        }
        .background(Theme.Colors.paper.ignoresSafeArea())
    }
}

struct WorkoutSessionView: View {
    @Environment(WorkoutUI.self) private var ui
    @Environment(HubStore.self) private var hub
    @Bindable var session: WorkoutSessionModel
    @State private var confirmEnd = false
    @State private var noteOpen = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GoldBar(value: session.progress).padding(.horizontal, Theme.Spacing.l)
            ScrollView {
                switch session.phase {
                case .warmup: warmup
                case .work: work
                case .rest: rest
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .confirmationDialog("End this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            if !session.sets.isEmpty {
                Button("Save \(session.sets.count) set\(session.sets.count == 1 ? "" : "s") and end") { ui.end() }
            }
            Button("Throw it away", role: .destructive) { ui.abandon() }
        }
    }

    private var topBar: some View {
        HStack {
            Button("End") { if session.sets.isEmpty && session.phase == .warmup { ui.abandon() } else { confirmEnd = true } }
                .foregroundStyle(Theme.Colors.inkSoft)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text("Workout \(session.def.id.rawValue) · \(WorkoutPlan.formatTime(Int(ctx.date.timeIntervalSince(session.startedAt))))")
                    .font(Theme.Typography.display(17, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.ink)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 1)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 48)
    }

    // MARK: Warm-up

    private var warmup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Warm up first", color: Theme.Colors.birthday)
                Text(session.def.title)
                    .font(Theme.Typography.display(34, .black, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.Colors.ink)
                Text("\(session.steps.count) sets · about \(session.def.estimatedMinutes) min")
                    .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
            }
            MusclesWorked(muscles: session.def.muscles, title: "Muscles worked")
            Text("Five minutes of easy cardio, then a light set of the first exercise.")
                .font(Theme.Typography.display(17, .italic))
                .foregroundStyle(Theme.Colors.inkSoft)
            Button("Start the first set") { session.startFirstSet() }
                .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 56))
        }
        .padding(Theme.Spacing.l)
    }

    // MARK: A set

    @ViewBuilder
    private var work: some View {
        if let step = session.step {
            let ex = step.exercise
            let log = hub.state.workouts
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "\(step.blockLabel) · Set \(step.setNumber) of \(step.totalSets)" +
                            (step.partnerName != nil || step.pairSecond ? " · superset" : ""),
                            color: Theme.Colors.birthday)
                    Text(ex.name)
                        .font(Theme.Typography.display(34, .black, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    MusclesWorked(muscles: ex.muscles, mapWidth: 40).padding(.top, 4)
                }

                let w = session.weight(for: ex)
                BigStepper(label: "Weight" + (ex.weightNote.map { " · \($0)" } ?? ""),
                           value: WorkoutEngine.formatWeight(w), unit: "lb",
                           minus: { withAnimation { session.adjustWeight(ex, by: -1) } },
                           plus: { withAnimation { session.adjustWeight(ex, by: 1) } },
                           footnote: ex.capNote.flatMap { w >= $0.atWeight ? $0.note : nil })

                BigStepper(label: "\(ex.timed ? "Seconds" : "Reps") · aim for \(ex.repsLabel)",
                           value: "\(session.reps)",
                           minus: { withAnimation { session.reps = max(0, session.reps - 1) } },
                           plus: { withAnimation { session.reps += 1 } },
                           footnote: lastTime(ex, log))

                if let note = ex.note {
                    Text(note)
                        .font(Theme.Typography.display(16, .italic))
                        .foregroundStyle(Theme.Colors.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let last = WorkoutEngine.lastNote(ex.id, in: log) {
                    Label("Last time: \(last)", systemImage: "note.text")
                        .font(.footnote).foregroundStyle(Theme.Colors.missed)
                }
                noteField(ex)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if session.advance(log: true) { ui.end() }
                } label: { Text("Log set").font(.title3.weight(.semibold)) }
                .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 56))

                HStack {
                    Text(session.nextUpText).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    Spacer()
                    Button("Skip") { if session.advance(log: false) { ui.end() } }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.inkSoft)
                }
            }
            .padding(Theme.Spacing.l)
        }
    }

    private func lastTime(_ ex: Exercise, _ log: WorkoutLog) -> String? {
        guard let p = WorkoutEngine.lastPerf(ex.id, in: log) else { return nil }
        let day = p.date.formatted(.dateTime.weekday(.abbreviated))
        return "Last time, \(day): \(WorkoutEngine.formatWeight(p.weight)) × " + p.reps.map(String.init).joined(separator: ", ")
    }

    @ViewBuilder
    private func noteField(_ ex: Exercise) -> some View {
        let binding = Binding(get: { session.exerciseNotes[ex.id] ?? "" }, set: { session.exerciseNotes[ex.id] = $0 })
        if noteOpen || !(session.exerciseNotes[ex.id] ?? "").isEmpty {
            TextField("Note for next time", text: binding, axis: .vertical)
                .padding(12)
                .paperCard(radius: 12)
        } else {
            Button { noteOpen = true } label: { Label("Add a note", systemImage: "square.and.pencil") }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.inkSoft)
        }
    }

    // MARK: Rest

    private var rest: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(0, Int(((session.restEndsAt ?? ctx.date).timeIntervalSince(ctx.date)).rounded(.up)))
            VStack(spacing: Theme.Spacing.l) {
                Eyebrow(text: "Rest")
                ZStack {
                    Circle().fill(Theme.Colors.card)
                    Circle().stroke(Theme.Colors.rule, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: session.restTotal > 0 ? CGFloat(left) / CGFloat(session.restTotal) : 0)
                        .stroke(Theme.Colors.gold, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: left)
                    Circle()
                        .inset(by: 22)
                        .stroke(Theme.Colors.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 9]))
                    VStack(spacing: 2) {
                        Text(WorkoutPlan.formatTime(left))
                            .font(Theme.Typography.display(72, .black, relativeTo: .largeTitle))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.ink)
                        Text("of \(WorkoutPlan.formatTime(session.restTotal))")
                            .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    }
                }
                .frame(width: 270, height: 270)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(left) seconds of rest left")

                HStack(spacing: 12) {
                    Button("− 15s") { session.adjustRest(by: -15) }
                        .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                    Button("+ 15s") { session.adjustRest(by: 15) }
                        .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                    Button("Skip") { session.endRest() }
                        .buttonStyle(PillButtonStyle(fill: Theme.Colors.ink, text: Theme.Colors.paper))
                }

                if let next = session.step {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Next · \(next.blockLabel) · set \(next.setNumber) of \(next.totalSets)")
                        HStack {
                            Text(next.exercise.name).font(Theme.Typography.rowTitle).foregroundStyle(Theme.Colors.ink)
                            Spacer()
                            Text("\(WorkoutEngine.formatWeight(session.weight(for: next.exercise))) lb")
                                .font(Theme.Typography.display(18, .bold)).foregroundStyle(Theme.Colors.ink)
                        }
                        if let partner = next.partnerName {
                            Text("Then \(partner), no rest").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .paperCard()
                }
            }
            .padding(Theme.Spacing.l)
            .onChange(of: left == 0) { _, done in
                if done && session.phase == .rest { session.endRest() }
            }
        }
    }
}

/// Muscle tags that wrap onto a second line.
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(tags, id: \.self) { TagPill(text: $0) }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            var s = v.sizeThatFits(.unspecified)
            if s.width > width { s = v.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            var s = v.sizeThatFits(.unspecified)
            if s.width > bounds.width { s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct WorkoutSummaryView: View {
    @Environment(WorkoutUI.self) private var ui
    @Environment(HubStore.self) private var hub
    let finished: WorkoutUI.Finished
    @State private var note = ""
    @State private var bumped: Set<String> = []

    var body: some View {
        let rows = WorkoutEngine.summary(finished.session, def: finished.def, graduations: finished.graduations)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "\(finished.session.startDate.formatted(.dateTime.weekday(.wide))) · Workout \(finished.def.id.rawValue)",
                            color: Theme.Colors.onBirthday)
                    Text("Done in \(max(1, finished.session.durationSec / 60)) min")
                        .font(Theme.Typography.display(34, .black, relativeTo: .largeTitle))
                    Text("\(finished.session.sets.count) sets · \(WorkoutEngine.weekStreak(hub.state.workouts)) week streak")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                .foregroundStyle(Theme.Colors.onBirthday)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.l)
                .background {
                    ZStack {
                        Theme.Colors.birthday
                        ConfettiField(seed: 21, count: 40, colors: Theme.Colors.confettiOnBirthday)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero))
                .padding(.top, Theme.Spacing.l)

                ForEach(finished.graduations, id: \.self) { g in
                    Label("You graduated from \(g.from.name) to \(g.to.name).", systemImage: "graduationcap.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.onGold)
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.gold, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }

                let worked = rows.reduce(into: [String]()) { out, row in
                    for m in row.exercise.muscles where !out.contains(m) { out.append(m) }
                }
                if !worked.isEmpty {
                    SectionTitle(title: "Muscles worked")
                    MusclesWorked(muscles: worked, mapWidth: 50)
                        .padding(Theme.Spacing.l)
                        .paperCard()
                }

                SectionTitle(title: "How it went")
                RuledCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { HairRule() }
                        summaryRow(row)
                    }
                }

                TextField("How did it feel? Add a note", text: $note, axis: .vertical)
                    .padding(14)
                    .paperCard(radius: 12)

                Button("Done") { ui.closeSummary(note: note) }
                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 52))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private func summaryRow(_ row: WorkoutEngine.SummaryRow) -> some View {
        let ex = row.exercise
        let w = row.logged.last?.weight ?? 0
        return HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ex.name).font(.body.weight(.semibold)).foregroundStyle(Theme.Colors.ink)
                    if row.hitTop { TagPill(text: "Hit the top", fill: Theme.Colors.gold, color: Theme.Colors.onGold) }
                }
                Text("\(WorkoutEngine.formatWeight(w)) lb · " + row.logged.map { "\($0.reps)" }.joined(separator: ", ") + (ex.timed ? " sec" : ""))
                    .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
            Spacer(minLength: 0)
            if row.hitTop, row.graduatedTo == nil {
                Button(bumped.contains(ex.id) ? "Bumped" : "+\(WorkoutEngine.formatWeight(ex.weightStep)) lb") {
                    guard !bumped.contains(ex.id) else { return }
                    bumped.insert(ex.id)
                    hub.update { $0.workouts.weights[ex.id] = WorkoutEngine.roundWeight(w + ex.weightStep) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.acted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Theme.Colors.acted, lineWidth: 1.5))
                .disabled(bumped.contains(ex.id))
                .accessibilityLabel("Add \(WorkoutEngine.formatWeight(ex.weightStep)) pounds next time")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
