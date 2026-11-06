import SwiftUI

/// Add a birthday or anniversary from the app. Saved into Contacts.
struct AddOccasionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: OccasionKind = .birthday
    @State private var contact: ContactSnapshot?
    @State private var newName = ""
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var knowsYear = false
    @State private var choosing = false
    @State private var partner: ContactSnapshot?
    @State private var choosingPartner = false
    @State private var saving = false

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
}
