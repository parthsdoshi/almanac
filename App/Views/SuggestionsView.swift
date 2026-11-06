import SwiftUI

struct SuggestionsView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var sheet: SuggestionSheet?
    @State private var confirmReplace: BirthdaySuggestion?

    private enum SuggestionSheet: Identifiable {
        case event(String), contact(String), choose(BirthdaySuggestion)
        var id: String {
            switch self {
            case .event(let id): "event-\(id)"
            case .contact(let id): "contact-\(id)"
            case .choose(let s): "choose-\(s.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeader(title: "Suggestions").screenHeaderRow()
                }
                if model.hasScannedCalendar && model.suggestions.isEmpty {
                    ContentUnavailableView(
                        "Nothing to add",
                        systemImage: "checkmark.circle",
                        description: Text("Every birthday in your calendar is already in Contacts.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !model.suggestions.isEmpty {
                    Section {
                        ForEach(model.suggestions) { s in
                            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                                HStack(spacing: Theme.Spacing.m) {
                                    DateChip(date: chipDate(s.date), kind: .birthday)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name)
                                            .font(Theme.Typography.rowTitle)
                                            .foregroundStyle(Theme.Colors.ink)
                                        Text("\(dateText(s.date)) · \(s.calendarTitle.map { "from \($0)" } ?? "in your calendar")")
                                            .font(Theme.Typography.rowSubtitle)
                                            .foregroundStyle(Theme.Colors.inkSoft)
                                    }
                                }
                                HStack(spacing: Theme.Spacing.l) {
                                    if let eventID = s.eventID {
                                        linkButton("Event", systemImage: "calendar") { sheet = .event(eventID) }
                                    }
                                    if let contactID = s.contactID {
                                        linkButton(s.contactName ?? "Contact", systemImage: "person.crop.circle") { sheet = .contact(contactID) }
                                    }
                                    linkButton(s.contactID == nil ? "Pick contact" : "Change", systemImage: "arrow.triangle.swap") { sheet = .choose(s) }
                                }
                                if let existing = s.existingBirthday {
                                    Text("\(s.contactName ?? "They") already has a birthday on \(dateText(existing)). Adding replaces it.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.missed)
                                }
                                HStack(spacing: 10) {
                                    Button(s.contactName.map { "Add to \($0)" } ?? "Create contact") {
                                        if s.existingBirthday != nil {
                                            confirmReplace = s
                                        } else {
                                            Task { await model.accept(s) }
                                        }
                                    }
                                    .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday))
                                    Button("Dismiss") { model.dismiss(s) }
                                        .buttonStyle(PillButtonStyle(fill: Theme.Colors.sunk, text: Theme.Colors.ink, border: Theme.Colors.rule))
                                }
                            }
                            .padding(.vertical, Theme.Spacing.s)
                        }
                        .listRowBackground(Theme.Colors.card)
                    } header: {
                        Text("Birthdays on your calendar that aren't in Contacts yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.inkSoft)
                            .textCase(nil)
                    }
                }
            }
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .overlay {
                if !model.hasScannedCalendar {
                    ContentUnavailableView {
                        Label("Birthdays in your calendar", systemImage: "calendar.badge.plus")
                            .foregroundStyle(Theme.Colors.ink)
                    } description: {
                        Text("Find birthday events in your calendar that aren't in your contacts yet.")
                            .foregroundStyle(Theme.Colors.inkSoft)
                    } actions: {
                        Button(scanning ? "Scanning…" : "Scan calendar") {
                            scanning = true
                            Task { await model.scanCalendar(); scanning = false }
                        }
                        .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday))
                        .frame(maxWidth: 220)
                        .disabled(scanning)
                    }
                }
            }
            .tabScreen("Suggestions")
            .refreshable { await model.scanCalendar() }
            .sheet(item: $sheet) { which in
                switch which {
                case .event(let id):
                    CalendarEventSheet(event: model.calendarEvent(id: id)) { sheet = nil }
                        .ignoresSafeArea()
                case .contact(let id):
                    ContactCardSheet(contactID: id) { sheet = nil }
                        .ignoresSafeArea()
                case .choose(let s):
                    ContactChooser(contacts: model.contactChoices) { picked in
                        model.relink(s, to: picked)
                    }
                }
            }
            .confirmationDialog(
                "Replace \(confirmReplace?.contactName ?? "their") birthday?",
                isPresented: Binding(get: { confirmReplace != nil }, set: { if !$0 { confirmReplace = nil } }),
                titleVisibility: .visible,
                presenting: confirmReplace
            ) { s in
                Button("Replace with \(dateText(s.date))", role: .destructive) {
                    Task { await model.accept(s) }
                }
            }
        }
    }

    private func linkButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .tint(Theme.Colors.accent)
    }

    /// Only used to draw the month and day on the chip. 2000 is a leap year, so Feb 29 works.
    private func chipDate(_ date: MonthDay) -> Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: date.month, day: date.day)) ?? .now
    }

    private func dateText(_ date: MonthDay) -> String {
        let d = Calendar.current.date(from: DateComponents(year: 2000, month: date.month, day: date.day)) ?? .now
        return d.formatted(.dateTime.month(.wide).day())
    }
}
