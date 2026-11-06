import SwiftUI

/// Add a birthday or anniversary from the app. Saved into Contacts.
struct AddOccasionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// A line typed elsewhere (Today's capture), read as soon as the sheet opens.
    var initialText: String? = nil

    @State private var kind: OccasionKind = .birthday
    @State private var contact: ContactSnapshot?
    @State private var newName = ""
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var knowsYear = false
    @State private var choosing = false
    @State private var partner: ContactSnapshot?
    @State private var choosingPartner = false
    @State private var saving = false
    @State private var quick = ""
    @State private var reading = false
    @State private var quickNote: String?
    @State private var whoOptions: [ContactSnapshot] = []
    @State private var partnerOptions: [ContactSnapshot] = []

    private var monthDay: MonthDay {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return MonthDay(month: c.month ?? 1, day: c.day ?? 1, year: knowsYear ? c.year : nil)
    }

    private var canSave: Bool {
        contact != nil || !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Picking a contact who already has a birthday replaces it.
    private var replaces: MonthDay? {
        kind == .birthday ? contact?.birthday : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Mom's birthday is March 3", text: $quick)
                            .submitLabel(.done)
                            .onSubmit(fill)
                        if reading {
                            ProgressView()
                        } else if !quick.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: fill) { Image(systemName: "sparkles") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Fill in from what I typed")
                        }
                    }
                } header: {
                    Text("Type it")
                } footer: {
                    Text(quickNote ?? "Say who, when, and birthday or anniversary. The rest of this form fills in.")
                }
                .listRowBackground(Theme.Colors.card)
                .onAppear {
                    if let t = initialText, quick.isEmpty {
                        quick = t
                        fill()
                    }
                }

                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(OccasionKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                Section("Who") {
                    if let contact {
                        HStack {
                            Text(ContactChooser.name(contact))
                            Spacer()
                            Button("Change") { choosing = true }
                                .buttonStyle(.borderless)
                        }
                    } else {
                        ForEach(whoOptions, id: \.id) { option in
                            Button("Use \(ContactChooser.name(option))") {
                                contact = option
                                newName = ""
                                whoOptions = []
                            }
                        }
                        Button("Choose from Contacts") { choosing = true }
                        TextField("Or type a new name", text: $newName)
                            .textContentType(.name)
                    }
                }
                .listRowBackground(Theme.Colors.card)

                if kind == .anniversary {
                    Section {
                        if let partner {
                            HStack {
                                Text(ContactChooser.name(partner))
                                Spacer()
                                Button("Remove") { self.partner = nil }
                                    .buttonStyle(.borderless)
                            }
                        } else {
                            ForEach(partnerOptions, id: \.id) { option in
                                Button("With \(ContactChooser.name(option))") {
                                    partner = option
                                    partnerOptions = []
                                }
                            }
                            Button("Choose their partner") { choosingPartner = true }
                        }
                    } header: {
                        Text("With")
                    } footer: {
                        Text("Links them as spouses in Contacts, so it shows as one anniversary for the couple and Message texts both.")
                    }
                    .listRowBackground(Theme.Colors.card)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("I know the year", isOn: $knowsYear)
                        .tint(Theme.Colors.acted)
                } header: {
                    Text("When")
                } footer: {
                    if let replaces {
                        Text("\(contact.map(ContactChooser.name) ?? "They") already has a birthday on \(ContactChooser.dateText(replaces)). Saving replaces it.")
                            .foregroundStyle(Theme.Colors.missed)
                    } else {
                        Text(knowsYear
                             ? (kind == .birthday ? "With the year, you'll see the age they turn." : "With the year, you'll see how many years it's been.")
                             : "The year is optional.")
                    }
                }
                .listRowBackground(Theme.Colors.card)
            }
            .paperBackground()
            .navigationTitle("Add \(kind.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let ok = await model.addOccasion(
                                kind: kind, date: monthDay, contactID: contact?.id,
                                newName: newName.trimmingCharacters(in: .whitespaces),
                                spouseName: kind == .anniversary ? partner.map(ContactChooser.name) : nil)
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSave || saving)
                }
            }
            .sheet(isPresented: $choosingPartner) {
                ContactChooser(contacts: model.contactChoices) { partner = $0 }
            }
            .sheet(isPresented: $choosing) {
                ContactChooser(contacts: model.contactChoices) { picked in
                    contact = picked
                    newName = ""
                }
            }
        }
    }

    private func fill() {
        let text = quick.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !reading else { return }
        reading = true
        Task {
            let guess = await QuickAdd.guess(text)
            apply(guess)
            reading = false
        }
    }

    private func apply(_ g: QuickAddGuess) {
        kind = g.kind
        let cal = Calendar.current
        if let m = g.month, let d = g.day {
            var y = g.year ?? cal.component(.year, from: .now)
            if g.year == nil, m == 2, d == 29 {
                while !(y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) { y += 1 }
            }
            if let picked = cal.date(from: DateComponents(year: y, month: m, day: d)) { date = picked }
            knowsYear = g.year != nil
        }

        contact = nil
        partner = nil
        newName = ""
        whoOptions = []
        partnerOptions = []
        let people = model.contactChoices
        if let first = g.names.first {
            let found = ContactMatcher.matches(for: first, in: people)
            if let sure = ContactMatcher.sure(found) {
                contact = sure
            } else if found.isEmpty {
                newName = first
            } else {
                whoOptions = found.map(\.contact)
                newName = first
            }
        }
        if g.kind == .anniversary, g.names.count > 1 {
            let found = ContactMatcher.matches(for: g.names[1], in: people)
            if let sure = ContactMatcher.sure(found) {
                partner = sure
            } else {
                partnerOptions = found.map(\.contact)
            }
        }

        var missing: [String] = []
        if g.names.isEmpty { missing.append("who it's for") }
        if g.month == nil { missing.append("the date") }
        if !missing.isEmpty {
            quickNote = "Couldn't tell \(missing.joined(separator: " or ")). Fill that in below."
        } else if !whoOptions.isEmpty {
            quickNote = "A few contacts fit \"\(g.names[0])\". Pick one below, or keep it as a new contact."
        } else {
            quickNote = "Filled in below. Check it, then Save."
        }
    }
}
