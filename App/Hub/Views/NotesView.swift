import SwiftUI

struct NotesView: View {
    @Environment(HubStore.self) private var hub
    @State private var query = ""
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ScreenHeader(title: "Notes", eyebrow: hub.state.notes.count == 1 ? "1 note" : "\(hub.state.notes.count) notes")
                        .screenHeaderRow()
                }
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.notes) { note in
                            NavigationLink(value: note.id) { NoteCard(note: note) }
                                .listRowBackground(Theme.Colors.card)
                                .swipeActions {
                                    Button(role: .destructive) { hub.deleteNote(note.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        SectionTitle(title: section.title)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .overlay {
                if hub.state.notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text",
                                           description: Text("Tap + to start one, or jot something on Today."))
                        .foregroundStyle(Theme.Colors.inkSoft)
                } else if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .tabScreen("Notes")
            .searchable(text: $query, prompt: "Search notes")
            .navigationDestination(for: UUID.self) { id in NoteEditorView(noteID: id) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let n = hub.addNote(body: "")
                        path.append(n.id)
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note")
                }
            }
            .onAppear {
                // Drop notes left empty.
                for n in hub.state.notes where n.title.isEmpty && n.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !path.contains(n.id) {
                    hub.deleteNote(n.id)
                }
            }
        }
    }

    private struct NoteSection {
        let title: String
        let notes: [Note]
    }

    private var sections: [NoteSection] {
        let q = query.lowercased()
        let notes = hub.state.notes
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) || $0.tags.contains { $0.contains(q) } }
            .sorted { $0.updated > $1.updated }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = notes.filter { $0.updated >= weekAgo }
        let older = notes.filter { $0.updated < weekAgo }
        return [NoteSection(title: "This week", notes: recent), NoteSection(title: "Earlier", notes: older)]
            .filter { !$0.notes.isEmpty }
    }
}

private struct NoteCard: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title.isEmpty ? firstLine : note.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
                Spacer()
                Text(note.updated.friendly(withTime: false))
                    .font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .lineLimit(2)
            }
            if !note.tags.isEmpty {
                HStack(spacing: 6) { ForEach(note.tags, id: \.self) { TagPill(text: $0) } }
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var firstLine: String {
        let l = note.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return l.isEmpty ? "New note" : l
    }

    private var preview: String {
        note.title.isEmpty ? note.body.split(whereSeparator: \.isNewline).dropFirst().joined(separator: " ") : note.body
    }
}

struct NoteEditorView: View {
    @Environment(HubStore.self) private var hub
    @Environment(AppModel.self) private var model
    let noteID: UUID
    @State private var note = Note(title: "", body: "")
    @State private var loaded = false
    @State private var tidy: NoteTidy?
    @State private var tidying = false
    @State private var picked: Set<String> = []
    @State private var added: String?
    @FocusState private var bodyFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Eyebrow(text: note.created.formatted(.dateTime.weekday(.wide).month(.wide).day()).replacingOccurrences(of: ",", with: " ·"))
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(Theme.Typography.display(34, .black, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.Colors.ink)
                if !note.tags.isEmpty {
                    HStack(spacing: 6) { ForEach(note.tags, id: \.self) { TagPill(text: $0) } }
                }
                TextField("Write anything", text: $note.body, axis: .vertical)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.Colors.ink)
                    .focused($bodyFocused)
                    .frame(minHeight: 200, alignment: .top)

                if let tidy { tidyCard(tidy) }
                if let added {
                    Label(added, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.acted)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                Button {
                    Task { await runTidy() }
                } label: {
                    if tidying { ProgressView() } else { Label("Tidy up", systemImage: "sparkles").labelStyle(.titleAndIcon) }
                }
                .disabled(note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tidying)
            }
        }
        .onAppear {
            guard !loaded, let n = hub.state.notes.first(where: { $0.id == noteID }) else { return }
            note = n
            loaded = true
            if n.body.isEmpty { bodyFocused = true }
        }
        .onChange(of: note) { _, new in if loaded { hub.saveNote(new) } }
    }

    private var shareText: String { note.title.isEmpty ? note.body : "\(note.title)\n\n\(note.body)" }

    private func runTidy() async {
        bodyFocused = false
        tidying = true
        let t = await NoteTidier.tidy(note)
        tidying = false
        tidy = t
        picked = Set(t.todos.map(\.id))
        added = nil
    }

    private func tidyCard(_ t: NoteTidy) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SparkleEyebrow(text: OnDevice.isAvailable ? "Tidied on your iPhone" : "Tidied", color: Theme.Colors.missed)
            HStack(spacing: 8) {
                Text("Title").font(.footnote).foregroundStyle(Theme.Colors.inkSoft).frame(width: 40, alignment: .leading)
                Text(t.title).font(Theme.Typography.display(17, .bold)).foregroundStyle(Theme.Colors.ink)
                Spacer()
            }
            if !t.tags.isEmpty {
                HStack(spacing: 6) {
                    Text("Tags").font(.footnote).foregroundStyle(Theme.Colors.inkSoft).frame(width: 40, alignment: .leading)
                    ForEach(t.tags, id: \.self) { TagPill(text: $0) }
                }
            }
            if !t.todos.isEmpty {
                SectionTitle(title: "To-dos it found").padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach(t.todos) { todo in
                        TodoRow(title: todo.text, detail: todo.due.map { $0.friendly(withTime: false) },
                                done: picked.contains(todo.id)) {
                            if picked.contains(todo.id) { picked.remove(todo.id) } else { picked.insert(todo.id) }
                        }
                    }
                }
            } else {
                Text("No to-dos in this one.").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
            HStack(spacing: 10) {
                Button("Use title and tags") {
                    note.title = t.title
                    note.tags = t.tags
                }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                if !picked.isEmpty {
                    Button("Add \(picked.count) to Reminders") { Task { await addTodos(t) } }
                        .buttonStyle(PillButtonStyle(fill: Theme.Colors.gold, text: Theme.Colors.onGold))
                }
            }
        }
        .padding(Theme.Spacing.l)
        .paperCard()
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.gold, lineWidth: 1.5))
    }

    private func addTodos(_ t: NoteTidy) async {
        var count = 0
        for todo in t.todos where picked.contains(todo.id) {
            do {
                try await RemindersService.shared.add(todo.text, due: todo.due, hasTime: false,
                                                      notes: note.title.isEmpty ? nil : "From your note \(note.title)")
                count += 1
            } catch {
                model.alertMessage = error.localizedDescription
                break
            }
        }
        if count > 0 {
            added = count == 1 ? "Added 1 to Reminders" : "Added \(count) to Reminders"
            picked = []
        }
    }
}
