import PhotosUI
import SwiftUI
import UIKit

/// When a to-do is due: the day it says, a rough "by when", or a picked date.
enum WhenChoice: Hashable {
    case stated
    case horizon(Horizon)
    case pick

    func resolve(stated: Date?, statedHasTime: Bool, picked: Date) -> (date: Date?, hasTime: Bool) {
        switch self {
        case .stated: (stated, statedHasTime)
        case .horizon(let h): (h.date(), false)
        case .pick: (Calendar.current.startOfDay(for: picked), false)
        }
    }

    func label(stated: Date?, statedHasTime: Bool, picked: Date) -> String {
        switch self {
        case .stated: stated?.friendly(withTime: statedHasTime) ?? "As typed"
        case .horizon(let h): h.label
        case .pick: picked.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}

/// Type a line (or several to-dos at once), see what it reads as, file it in one tap.
struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HubStore.self) private var hub
    @Environment(\.dismiss) private var dismiss
    /// Opens Add with the line, for a birthday or anniversary.
    var onOccasion: (String) -> Void = { _ in }

    struct Todo: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var due: Date?
        var dueHasTime: Bool
        var when: WhenChoice
        var picked = Date.now
        var guessed = true

        init(_ g: CaptureGuess) {
            text = g.text
            due = g.due
            dueHasTime = g.dueHasTime
            when = g.due != nil ? .stated : .horizon(g.horizon)
            guessed = g.due == nil
        }

        var resolved: (date: Date?, hasTime: Bool) { when.resolve(stated: due, statedHasTime: dueHasTime, picked: picked) }
        var whenLabel: String { when.label(stated: due, statedHasTime: dueHasTime, picked: picked) }
    }

    @State private var text = ""
    @State private var guess: CaptureGuess?
    @State private var single: Todo?
    @State private var list: [Todo] = []
    @State private var listAsNote = false
    @State private var reading = false
    @State private var personID: String?
    @State private var saving = false
    @State private var readTask: Task<Void, Never>?
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var takingPhoto = false
    @State private var photo: UIImage?
    @State private var readingPhoto = false
    @State private var photoMiss = false
    @FocusState private var focused: Bool

    private var isList: Bool { list.count >= 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if photo != nil || readingPhoto { photoHeader }

                    HStack(alignment: .top, spacing: 10) {
                        TextField("Remind me to…, a few to-dos, an idea, a birthday", text: $text, axis: .vertical)
                            .font(.title3)
                            .lineLimit(2...8)
                            .focused($focused)
                            .onChange(of: text) { _, _ in scheduleRead() }
                        photoButton
                    }
                    .padding(14)
                    .paperCard(radius: 12)

                    if isList {
                        readsAs
                        listPicker
                        if listAsNote {
                            Text("Saves to Notes as written.")
                                .font(.subheadline).foregroundStyle(Theme.Colors.inkSoft)
                        } else {
                            listCard
                        }
                    } else if let g = guess {
                        readsAs
                        kindPicker(g)
                        details(g)
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.paper)
            .navigationTitle("Jot it down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saveDisabled)
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
            .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    await readPhoto(image)
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    takingPhoto = false
                    if let image { Task { await readPhoto(image) } }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Photo

    private var photoButton: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button { takingPhoto = true } label: { Label("Take photo", systemImage: "camera") }
            }
            Button { choosingPhoto = true } label: { Label("Choose from Photos", systemImage: "photo") }
        } label: {
            Image(systemName: "camera")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.birthday)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Colors.birthday.opacity(0.12)))
        }
        .accessibilityLabel("Add from a photo")
    }

    private var photoHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SparkleEyebrow(text: "Read from your photo")
                    if readingPhoto { ProgressView().controlSize(.mini) }
                }
                Text(readingPhoto ? "Reading the words on it…" : photoMiss ? "Couldn't find any words. Type it instead." : "Check it below, then add it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            Spacer(minLength: 0)
            if photo != nil, !readingPhoto {
                Button { photo = nil; photoMiss = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.inkSoft)
                }
                .accessibilityLabel("Remove photo")
            }
        }
    }

    private func readPhoto(_ image: UIImage) async {
        let upright = image.uprightScaled(maxSide: 2048)
        photo = upright
        photoMiss = false
        guard let cg = upright.cgImage else { photoMiss = true; return }
        readingPhoto = true
        let read = await PhotoReader.read(cg)
        readingPhoto = false
        guard !read.lines.isEmpty else { photoMiss = true; return }
        let joined = read.lines.joined(separator: "\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? joined : text + "\n" + joined
    }

    private var readsAs: some View {
        HStack(spacing: 6) {
            SparkleEyebrow(text: "Reads as")
            if reading { ProgressView().controlSize(.mini) }
        }
    }

    // MARK: Several to-dos

    private var listPicker: some View {
        WrapLayout(spacing: 6) {
            chip("\(list.count) to-dos", selected: !listAsNote) { listAsNote = false }
            chip("One note", selected: listAsNote) { listAsNote = true }
        }
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach($list) { $todo in
                if todo.id != list.first?.id { HairRule() }
                HStack(spacing: 10) {
                    TextField("To-do", text: $todo.text, axis: .vertical)
                        .foregroundStyle(Theme.Colors.ink)
                    Spacer(minLength: 4)
                    whenMenu($todo)
                    Button {
                        list.removeAll { $0.id == todo.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.rule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(todo.text)")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
            }
            HairRule()
            HStack {
                Text("List").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                Spacer()
                Text(RemindersService.shared.defaultListTitle).font(.subheadline).foregroundStyle(Theme.Colors.ink)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .paperCard()
    }

    private func whenMenu(_ todo: Binding<Todo>) -> some View {
        Menu {
            if let d = todo.wrappedValue.due {
                Button(d.friendly(withTime: todo.wrappedValue.dueHasTime)) {
                    todo.wrappedValue.when = .stated; todo.wrappedValue.guessed = false
                }
            }
            ForEach(Horizon.allCases) { h in
                Button(h.label) { todo.wrappedValue.when = .horizon(h); todo.wrappedValue.guessed = false }
            }
        } label: {
            HStack(spacing: 3) {
                if todo.wrappedValue.guessed { Image(systemName: "sparkles").font(.caption2) }
                Text(todo.wrappedValue.whenLabel).lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
            .fixedSize()
        }
    }

    // MARK: One thing

    private func kindPicker(_ g: CaptureGuess) -> some View {
        WrapLayout(spacing: 6) {
            ForEach(CaptureGuess.Kind.allCases) { k in
                chip(k.label, selected: g.kind == k) {
                    guess?.kind = k
                    if k == .person, guess?.person == nil { guess?.person = RuleCapture.read(text).person }
                    if k == .reminder, single == nil { single = Todo(RuleCapture.todo(text)) }
                    matchPerson()
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.Colors.paper : Theme.Colors.inkSoft)
                .background(selected ? Theme.Colors.ink : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.Colors.ink : Theme.Colors.rule, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func details(_ g: CaptureGuess) -> some View {
        switch g.kind {
        case .reminder:
            if let s = Binding($single) { reminderCard(s) }
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

    private func reminderCard(_ todo: Binding<Todo>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text("To-do").font(.footnote).foregroundStyle(Theme.Colors.inkSoft).frame(width: 52, alignment: .leading)
                TextField("What to do", text: todo.text, axis: .vertical).foregroundStyle(Theme.Colors.ink)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            HairRule()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("When").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    if todo.wrappedValue.guessed {
                        SparkleEyebrow(text: OnDevice.isAvailable ? "Guessed" : "Default")
                    }
                }
                WrapLayout(spacing: 6) {
                    if let d = todo.wrappedValue.due {
                        chip(d.friendly(withTime: todo.wrappedValue.dueHasTime), selected: todo.wrappedValue.when == .stated) {
                            todo.wrappedValue.when = .stated; todo.wrappedValue.guessed = false
                        }
                    }
                    ForEach(Horizon.allCases) { h in
                        chip(h.label, selected: todo.wrappedValue.when == .horizon(h)) {
                            todo.wrappedValue.when = .horizon(h); todo.wrappedValue.guessed = false
                        }
                    }
                    chip("Pick a day", selected: todo.wrappedValue.when == .pick) {
                        todo.wrappedValue.when = .pick; todo.wrappedValue.guessed = false
                    }
                }
                if todo.wrappedValue.when == .pick {
                    DatePicker("Due", selection: todo.picked, displayedComponents: [.date])
                        .labelsHidden()
                }
                if let d = todo.wrappedValue.resolved.date, todo.wrappedValue.when != .stated, todo.wrappedValue.when != .pick {
                    Text("Due \(d.friendly(withTime: false))").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                }
            }
            .padding(14)
            HairRule()
            HStack(spacing: Theme.Spacing.m) {
                Text("List").font(.footnote).foregroundStyle(Theme.Colors.inkSoft).frame(width: 52, alignment: .leading)
                Text(RemindersService.shared.defaultListTitle).foregroundStyle(Theme.Colors.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
        .paperCard()
    }

    private var actionTitle: String {
        if isList { return listAsNote ? "Save" : "Add \(list.count)" }
        switch guess?.kind {
        case .reminder: return "Add"
        case .occasion: return "Next"
        default: return "Save"
        }
    }

    private var saveDisabled: Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving { return true }
        if isList { return false }
        return guess?.kind == .person && personID == nil
    }

    // MARK: Reading

    private func scheduleRead() {
        readTask?.cancel()
        let line = text
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { guess = nil; single = nil; list = []; return }
        // Rules answer instantly; the model refines after a short pause.
        applyRules(line)
        readTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, OnDevice.isAvailable else { return }
            reading = true
            defer { reading = false }
            let pieces = await ModelCapture.todos(in: line) ?? RuleCapture.split(line)
            guard !Task.isCancelled, line == text else { return }
            if pieces.count >= 2 {
                var todos: [Todo] = []
                for p in pieces.prefix(12) {
                    var g = RuleCapture.todo(p)
                    if g.due == nil, Horizon.stated(in: p.lowercased()) == nil, let h = await ModelCapture.horizon(for: p) { g.horizon = h }
                    todos.append(Todo(g))
                }
                guard !Task.isCancelled, line == text else { return }
                list = merge(todos, into: list)
            } else {
                list = []
                let g = await CaptureReader.read(line)
                guard !Task.isCancelled, line == text else { return }
                apply(g)
            }
        }
    }

    private func applyRules(_ line: String) {
        let pieces = RuleCapture.split(line)
        if pieces.count >= 2 {
            list = merge(pieces.prefix(12).map { Todo(RuleCapture.todo($0)) }, into: list)
        } else {
            list = []
            apply(RuleCapture.read(line))
        }
    }

    /// Keeps a choice the person already made on a row with the same text.
    private func merge(_ new: [Todo], into old: [Todo]) -> [Todo] {
        new.map { t in
            guard let o = old.first(where: { $0.text == t.text }), !o.guessed else { return t }
            var t = t
            t.when = o.when
            t.picked = o.picked
            t.guessed = false
            return t
        }
    }

    private func apply(_ g: CaptureGuess) {
        guess = g
        if g.kind == .reminder {
            let kept = single
            var s = Todo(g)
            if let kept, !kept.guessed, kept.when != .stated || g.due != nil {
                s.when = kept.when
                s.picked = kept.picked
                s.guessed = false
            }
            single = s
        } else {
            single = nil
        }
        matchPerson()
    }

    private func matchPerson() {
        guard let g = guess, g.kind == .person, let name = g.person else { personID = nil; return }
        personID = ContactMatcher.sure(ContactMatcher.matches(for: name, in: model.contactChoices))?.id
    }

    // MARK: Saving

    private func save() async {
        saving = true
        defer { saving = false }
        if isList {
            if listAsNote {
                hub.addNote(body: text.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
                return
            }
            var added = 0
            for t in list where !t.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let r = t.resolved
                do {
                    try await RemindersService.shared.add(t.text, due: r.date, hasTime: r.hasTime)
                    added += 1
                } catch {
                    model.alertMessage = added == 0 ? error.localizedDescription
                        : "Added \(added) of \(list.count). \(error.localizedDescription)"
                    return
                }
            }
            dismiss()
            return
        }

        let g = guess ?? RuleCapture.read(text)
        switch g.kind {
        case .reminder:
            let t = single ?? Todo(RuleCapture.todo(text))
            let r = t.resolved
            do {
                try await RemindersService.shared.add(t.text.isEmpty ? text : t.text, due: r.date, hasTime: r.hasTime)
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

/// The system camera, for Jot's "Take photo".
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

extension UIImage {
    /// Redrawn the right way up and no bigger than `maxSide`, so Vision and the
    /// model see what the person saw.
    func uprightScaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
