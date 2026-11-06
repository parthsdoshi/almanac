import SwiftUI
import UniformTypeIdentifiers

/// Which workout is on screen, shared by Today and the Workouts tab.
@MainActor
@Observable
final class WorkoutUI {
    static let shared = WorkoutUI()

    struct Finished: Identifiable {
        var id: String { session.date }
        let session: WorkoutSession
        let def: WorkoutDef
        let graduations: [WorkoutEngine.Graduation]
    }

    var active: WorkoutSessionModel?
    var finished: Finished?
    var resumable = WorkoutSessionModel.resumable

    var isPresented: Bool { active != nil || finished != nil }

    func start(_ id: WorkoutID, hub: HubStore = .shared) {
        WorkoutSessionModel.clearSaved()
        resumable = nil
        active = WorkoutSessionModel(def: WorkoutEngine.def(id, hub.state.workouts), hub: hub)
    }

    func resume() {
        active = WorkoutSessionModel.resume()
        resumable = nil
    }

    func discardResumable() {
        WorkoutSessionModel.clearSaved()
        resumable = nil
    }

    func end() {
        guard let a = active else { return }
        if let done = a.finish() {
            finished = Finished(session: done.session, def: a.def, graduations: done.graduations)
            let session = done.session
            Task { await HealthService.shared.save(session) }
        }
        active = nil
    }

    func abandon() {
        active?.discard()
        active = nil
    }

    func closeSummary(note: String, hub: HubStore = .shared) {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = finished, !t.isEmpty {
            hub.update { s in
                if let i = s.workouts.history.lastIndex(where: { $0.date == f.session.date }) { s.workouts.history[i].note = t }
            }
        }
        finished = nil
    }
}

struct WorkoutsView: View {
    @Environment(HubStore.self) private var hub
    @Environment(WorkoutUI.self) private var ui
    @State private var importing = false
    @State private var importResult: String?
    @State private var pendingImport: WorkoutLog?
    @State private var showOther = false
    @State private var loggingWeight = false

    private var log: WorkoutLog { hub.state.workouts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ScreenHeader(
                        title: "Workouts",
                        eyebrow: Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .replacingOccurrences(of: ",", with: "") + " · " + WorkoutPlan.dayKind(.now))

                    if let r = ui.resumable {
                        resumeCard(r)
                    }

                    statsRow
                    UpNextCard(def: WorkoutEngine.def(showOther ? WorkoutEngine.suggestedNext(log).other : WorkoutEngine.suggestedNext(log), log),
                               log: log,
                               onStart: { ui.start($0) },
                               onSwap: { withAnimation { showOther.toggle() } },
                               swapLabel: "Do \((showOther ? WorkoutEngine.suggestedNext(log) : WorkoutEngine.suggestedNext(log).other).rawValue) instead")

                    if !log.history.isEmpty {
                        SectionTitle(title: "Recent").padding(.top, Theme.Spacing.s)
                        RuledCard {
                            ForEach(Array(log.history.suffix(8).reversed().enumerated()), id: \.element.id) { i, s in
                                if i > 0 { HairRule() }
                                NavigationLink(value: s.id) { HistoryRow(session: s) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    } else {
                        importCard
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.paper)
            .tabScreen("Workouts")
            .navigationDestination(for: String.self) { id in
                if let s = log.history.first(where: { $0.id == id }) { SessionDetailView(session: s) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { loggingWeight = true } label: { Label("Log bodyweight", systemImage: "scalemass") }
                        Button { importing = true } label: { Label("Import web backup", systemImage: "square.and.arrow.down") }
                        if let url = exportURL() {
                            ShareLink(item: url) { Label("Export backup", systemImage: "square.and.arrow.up") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog(
                "Replace your workout log?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible
            ) {
                Button("Replace with \(pendingImport?.history.count ?? 0) sessions", role: .destructive) {
                    if let p = pendingImport { applyImport(p) }
                }
            } message: {
                Text("You have \(log.history.count) sessions here. The backup has \(pendingImport?.history.count ?? 0).")
            }
            .alert("Import", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importResult ?? "")
            }
            .sheet(isPresented: $loggingWeight) { BodyweightSheet().presentationDetents([.height(300)]) }
        }
    }

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            MiniStat(value: "\(WorkoutEngine.weekStreak(log))", label: "Week streak", symbol: "flame.fill")
            MiniStat(value: "\(WorkoutEngine.sessionsThisMonth(log))", label: "This month")
            if let bw = log.bodyweight.last {
                MiniStat(value: WorkoutEngine.formatWeight(bw.lb), label: "Lb · " + shortDay(bw.date))
            } else {
                Button { loggingWeight = true } label: { MiniStat(value: "–", label: "Log weight") }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Bring your history over")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text("On the web tracker, tap Export backup, save the file to Files, then import it here. Your weights, sessions and notes come with it.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.inkSoft)
            Button("Import backup") { importing = true }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.l)
        .paperCard()
    }

    private func resumeCard(_ r: (workout: WorkoutID, startedAt: Date, setsLogged: Int)) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Eyebrow(text: "Unfinished", color: Theme.Colors.missed)
            Text("Workout \(r.workout.rawValue), started \(r.startedAt.formatted(date: .omitted, time: .shortened)) · \(r.setsLogged) sets logged")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.ink)
            HStack(spacing: 10) {
                Button("Pick up") { ui.resume() }
                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.ink, text: Theme.Colors.paper))
                Button("Discard") { ui.discardResumable() }
                    .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
            }
        }
        .padding(Theme.Spacing.l)
        .paperCard()
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.gold, lineWidth: 1.5))
    }

    private func shortDay(_ ymd: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return ymd }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            importResult = e.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try WorkoutEngine.importBackup(try Data(contentsOf: url))
                if log.history.isEmpty { applyImport(parsed) } else { pendingImport = parsed }
            } catch {
                importResult = error.localizedDescription
            }
        }
    }

    private func applyImport(_ parsed: WorkoutLog) {
        hub.update { $0.workouts = parsed }
        pendingImport = nil
        importResult = "Imported \(parsed.history.count) session\(parsed.history.count == 1 ? "" : "s")."
    }

    /// The same backup shape the web app reads, so you can go back.
    private func exportURL() -> URL? {
        guard !log.history.isEmpty else { return nil }
        let payload: [String: Any] = [
            "app": "workout-tracker", "version": 1, "exportedAt": WorkoutDates.string(.now),
        ]
        guard let base = try? JSONSerialization.data(withJSONObject: payload),
              var dict = try? JSONSerialization.jsonObject(with: base) as? [String: Any],
              let logData = try? JSONEncoder().encode(log),
              let logDict = try? JSONSerialization.jsonObject(with: logData) as? [String: Any] else { return nil }
        for (k, v) in logDict { dict[k] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "workout-backup-\(WorkoutDates.dayString(.now)).json")
        try? data.write(to: url)
        return url
    }
}

struct MiniStat: View {
    let value: String
    let label: String
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(value)
                    .font(Theme.Typography.display(28, .black, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.ink)
                if let symbol {
                    Image(systemName: symbol).font(.subheadline).foregroundStyle(Theme.Colors.birthday)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.Colors.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

/// The ink-topped card with the next workout's blocks and a Start button.
struct UpNextCard: View {
    let def: WorkoutDef
    let log: WorkoutLog
    let onStart: (WorkoutID) -> Void
    var onSwap: (() -> Void)? = nil
    var swapLabel = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(def.id.rawValue)
                    .font(Theme.Typography.display(40, .black, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.Colors.goldOnInk)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Up next · about \(def.estimatedMinutes) min", color: Theme.Colors.goldOnInk)
                    Text(def.title)
                        .font(Theme.Typography.display(19, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.paper)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.ink)

            ForEach(Array(def.blocks.enumerated()), id: \.offset) { i, block in
                if i > 0 { HairRule() }
                BlockRow(block: block, log: log)
            }

            HStack(spacing: 10) {
                Button { onStart(def.id) } label: { Text("Start Workout \(def.id.rawValue)") }
                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 50))
                if let onSwap {
                    Button(swapLabel, action: onSwap)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.inkSoft)
                        .frame(width: 92)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .paperCard()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

private struct BlockRow: View {
    let block: WorkoutBlock
    let log: WorkoutLog

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(block.label)
                .font(Theme.Typography.display(16, .black))
                .foregroundStyle(Theme.Colors.inkSoft)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(names).font(.body.weight(.semibold)).foregroundStyle(Theme.Colors.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
            Spacer(minLength: 4)
            Text(weights)
                .font(Theme.Typography.display(16, .bold))
                .foregroundStyle(Theme.Colors.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var names: String {
        let ex = block.exercises
        return ex.count == 1 ? ex[0].name : ex.map(\.name).joined(separator: " + ")
    }

    private var detail: String {
        switch block {
        case .single(_, let sets, let rest, let ex):
            "\(sets) × \(ex.repsLabel) · \(WorkoutPlan.formatTime(rest)) rest"
        case .superset(_, let sets, let setsB, _, _, _):
            if let b = setsB, b != sets { "Superset · \(sets) + \(b) rounds" } else { "Superset · \(sets) rounds" }
        }
    }

    private var weights: String {
        block.exercises.map { ex in
            let w = log.weight(for: ex)
            return w == 0 ? "–" : WorkoutEngine.formatWeight(w)
        }.joined(separator: " · ") + (block.exercises.count == 1 && log.weight(for: block.exercises[0]) > 0 ? " lb" : "")
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(session.workout.rawValue)
                .font(Theme.Typography.display(20, .black))
                .foregroundStyle(Theme.Colors.ink)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.ink)
                Text("\(session.durationSec / 60) min · \(session.sets.count) sets" + (session.note.map { " · \($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Colors.rule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Workout \(session.workout.rawValue) · \(session.durationSec / 60) min")
                    Text(session.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(Theme.Typography.display(30, .black, relativeTo: .title))
                        .foregroundStyle(Theme.Colors.ink)
                    if let note = session.note {
                        Text(note).font(Theme.Typography.display(16, .italic)).foregroundStyle(Theme.Colors.inkSoft)
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groups) { g in
                Section {
                    Text(g.sets.map { "\(WorkoutEngine.formatWeight($0.weight)) × \($0.reps)" }.joined(separator: ",  "))
                        .foregroundStyle(Theme.Colors.ink)
                        .monospacedDigit()
                    if let n = session.exerciseNotes?[g.id] {
                        Text(n).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    }
                } header: {
                    SectionTitle(title: g.name)
                }
                .listRowBackground(Theme.Colors.card)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ExerciseGroup: Identifiable {
        let id: String
        let name: String
        let sets: [LoggedSet]
    }

    private var groups: [ExerciseGroup] {
        var order: [String] = []
        var by: [String: [LoggedSet]] = [:]
        for s in session.sets {
            if by[s.exerciseId] == nil { order.append(s.exerciseId) }
            by[s.exerciseId, default: []].append(s)
        }
        return order.map { ExerciseGroup(id: $0, name: by[$0]?.first?.name ?? $0, sets: by[$0] ?? []) }
    }
}

struct BodyweightSheet: View {
    @Environment(HubStore.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var lb: Double = 170

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Text("Bodyweight today")
                .font(Theme.Typography.display(20, .bold))
                .foregroundStyle(Theme.Colors.ink)
                .padding(.top, Theme.Spacing.l)
            BigStepper(label: "Pounds", value: WorkoutEngine.formatWeight(lb), unit: "lb",
                       minus: { lb = max(50, ((lb - 0.5) * 2).rounded() / 2) },
                       plus: { lb = ((lb + 0.5) * 2).rounded() / 2 })
            Button("Save") {
                let today = WorkoutDates.dayString(.now)
                hub.update { s in
                    s.workouts.bodyweight.removeAll { $0.date == today }
                    s.workouts.bodyweight.append(BodyweightEntry(date: today, lb: lb))
                    s.workouts.bodyweight.sort { $0.date < $1.date }
                }
                let saved = lb
                Task { await HealthService.shared.saveBodyweight(saved) }
                dismiss()
            }
            .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 50))
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.paper)
        .onAppear { if let last = hub.state.workouts.bodyweight.last { lb = last.lb } }
    }
}
