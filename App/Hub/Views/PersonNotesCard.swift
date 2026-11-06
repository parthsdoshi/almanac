import SwiftUI

/// "What you know" on a person's page: lines you've jotted about them, and a
/// text drafted from them.
struct PersonNotesCard: View {
    @Environment(HubStore.self) private var hub
    @Environment(AppModel.self) private var model
    let item: UpcomingItem
    @State private var adding = ""
    @State private var addingFor: String?
    @State private var draft: String?
    @State private var drafting = false
    @FocusState private var focused: Bool

    private var occasion: Occasion { item.occasion }
    private var notes: [PersonNote] { hub.notes(for: occasion.people.map(\.contactID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionTitle(title: "What you know")
            RuledCard {
                ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { HairRule() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.text).foregroundStyle(Theme.Colors.ink)
                        Text(label(n)).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contextMenu {
                        Button(role: .destructive) { hub.deletePersonNote(n.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                if !notes.isEmpty { HairRule() }
                HStack(spacing: 10) {
                    Image(systemName: "plus").foregroundStyle(Theme.Colors.inkSoft)
                    TextField("Add a note about \(Names.join(occasion.firstNames))", text: $adding, axis: .vertical)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                    if !adding.isEmpty {
                        Button("Add", action: save).font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            if occasion.people.count > 1, focused || !adding.isEmpty {
                Picker("About", selection: Binding(get: { addingFor ?? occasion.people[0].contactID }, set: { addingFor = $0 })) {
                    ForEach(occasion.people) { Text($0.firstName).tag($0.contactID) }
                }
                .pickerStyle(.segmented)
            }

            if !notes.isEmpty { draftCard }
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SparkleEyebrow(text: "Draft from your notes")
            if let draft {
                Text(draft)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.18, green: 0.49, blue: 0.96), in: UnevenRoundedRectangle(
                        topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button { model.beginMessage(occasion, body: draft) } label: { Label("Use this", systemImage: Theme.Icons.message) }
                        .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday))
                    Button("Try another") { Task { await makeDraft() } }
                        .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                        .disabled(drafting)
                }
            } else {
                Button { Task { await makeDraft() } } label: {
                    if drafting { ProgressView() } else { Label("Draft a text", systemImage: "sparkles") }
                }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink))
                .disabled(drafting)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Colors.sunk, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func label(_ n: PersonNote) -> String {
        let when = n.created.formatted(.dateTime.month(.abbreviated).day())
        guard occasion.people.count > 1, let p = occasion.people.first(where: { $0.contactID == n.contactID }) else { return when }
        return "\(p.firstName) · \(when)"
    }

    private func save() {
        let id = addingFor ?? occasion.people.first?.contactID
        guard let id else { return }
        hub.addPersonNote(adding, contactID: id)
        adding = ""
        draft = nil
    }

    private func makeDraft() async {
        drafting = true
        draft = await TextDrafter.draft(for: occasion, years: item.years, notes: notes.map(\.text),
                                        fallback: model.templateMessage(occasion))
        drafting = false
    }
}
