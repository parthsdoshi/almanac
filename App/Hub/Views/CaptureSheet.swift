import SwiftUI

/// Type a line, see what it reads as, file it in one tap.
struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HubStore.self) private var hub
    @Environment(\.dismiss) private var dismiss
    /// Opens Add with the line, for a birthday or anniversary.
    var onOccasion: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var guess: CaptureGuess?
    @State private var reading = false
    @State private var due = Date.now
    @State private var hasDue = false
    @State private var dueHasTime = false
    @State private var personID: String?
    @State private var saving = false
    @State private var readTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    TextField("Remind me to…, an idea, a birthday", text: $text, axis: .vertical)
                        .font(.title3)
                        .lineLimit(2...6)
                        .focused($focused)
                        .padding(14)
                        .paperCard(radius: 12)
                        .onChange(of: text) { _, _ in scheduleRead() }

                    if let g = guess {
                        HStack(spacing: 6) {
                            SparkleEyebrow(text: "Reads as")
                            if reading { ProgressView().controlSize(.mini) }
                        }
                        kindPicker(g)
                        details(g)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("Jot it down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || saving || (guess?.kind == .person && personID == nil))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(OnDevice.isAvailable ? "Read on your iPhone. Nothing you type leaves it." : "Nothing you type leaves your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Spacing.s)
            }
            .onAppear { focused = true }
        }
    }

    private func kindPicker(_ g: CaptureGuess) -> some View {
        WrapLayout(spacing: 6) {
            ForEach(CaptureGuess.Kind.allCases) { k in
                Button {
                    guess?.kind = k
                    if k == .person, guess?.person == nil { guess?.person = RuleCapture.read(text).person }
                    matchPerson()
                } label: {
                    Text(k.label)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(g.kind == k ? Theme.Colors.paper : Theme.Colors.inkSoft)
                        .background(g.kind == k ? Theme.Colors.ink : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(g.kind == k ? Theme.Colors.ink : Theme.Colors.rule, lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(g.kind == k ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func details(_ g: CaptureGuess) -> some View {
        switch g.kind {
        case .reminder:
            VStack(spacing: 0) {
                row("To-do") {
                    TextField("What to do", text: Binding(get: { guess?.text ?? "" }, set: { guess?.text = $0 }))
                }
                HairRule()
                row("When") {
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden()
                    } else {
                        Text("No date").foregroundStyle(Theme.Colors.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Toggle("Has a date", isOn: $hasDue)
                        .labelsHidden()
                        .tint(Theme.Colors.acted)
                }
                HairRule()
                row("List") { Text(RemindersService.shared.defaultListTitle).foregroundStyle(Theme.Colors.ink) }
            }
            .paperCard()
        case .note:
            Text("Saves to Notes as written. You can tidy it up there.")
                .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
        case .person:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                let matches = ContactMatcher.matches(for: g.person ?? "", in: model.contactChoices)
                if matches.isEmpty {
                    Text(g.person.map { "No contact matches \($0)." } ?? "Start with the person's name.")
                        .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
                } else {
                    Text("Save to").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    WrapLayout(spacing: 6) {
                        ForEach(matches, id: \.contact.id) { m in
                            Button { personID = m.contact.id } label: {
                                Text([m.contact.givenName, m.contact.familyName].filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .foregroundStyle(personID == m.contact.id ? Theme.Colors.onBirthday : Theme.Colors.ink)
                                    .background(personID == m.contact.id ? Theme.Colors.birthday : Theme.Colors.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.Colors.rule))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        case .occasion:
            Text("Opens Add with this filled in, so you can check the person and date.")
                .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(label).font(.footnote).foregroundStyle(Theme.Colors.inkSoft).frame(width: 52, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private var actionTitle: String {
        switch guess?.kind {
        case .reminder: "Add"
        case .occasion: "Next"
        default: "Save"
        }
    }

    private func scheduleRead() {
        readTask?.cancel()
        let line = text
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { guess = nil; return }
        // Rules answer instantly; the model refines after a short pause.
        apply(RuleCapture.read(line), keepKind: false)
        readTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, OnDevice.isAvailable else { return }
            reading = true
            let g = await CaptureReader.read(line)
            reading = false
            guard !Task.isCancelled, line == text else { return }
            apply(g, keepKind: false)
        }
    }

    private func apply(_ g: CaptureGuess, keepKind: Bool) {
        var g = g
        if keepKind, let k = guess?.kind { g.kind = k }
        guess = g
        hasDue = g.due != nil
        if let d = g.due { due = d }
        dueHasTime = g.dueHasTime
        matchPerson()
    }

    private func matchPerson() {
        guard let g = guess, g.kind == .person, let name = g.person else { personID = nil; return }
        personID = ContactMatcher.sure(ContactMatcher.matches(for: name, in: model.contactChoices))?.id
    }

    private func save() async {
        let g = guess ?? RuleCapture.read(text)
        saving = true
        defer { saving = false }
        switch g.kind {
        case .reminder:
            do {
                let title = g.text.isEmpty ? text : g.text
                try await RemindersService.shared.add(title, due: hasDue ? due : nil, hasTime: hasDue && dueHasTime)
                dismiss()
            } catch {
                model.alertMessage = error.localizedDescription
            }
        case .note:
            hub.addNote(body: text.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        case .person:
            guard let id = personID else { return }
            hub.addPersonNote(g.text.isEmpty ? text : g.text, contactID: id)
            dismiss()
        case .occasion:
            let line = text
            let open = onOccasion
            dismiss()
            // Let this sheet finish closing before Add opens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { open(line) }
        }
    }
}
