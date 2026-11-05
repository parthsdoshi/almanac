import SwiftUI

struct SuggestionsView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            List {
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
                                        Text("\(dateText(s.date)) · in your calendar")
                                            .font(Theme.Typography.rowSubtitle)
                                            .foregroundStyle(Theme.Colors.inkSoft)
                                    }
                                }
                                HStack(spacing: 10) {
                                    Button(s.contactName.map { "Add to \($0)" } ?? "Create contact") {
                                        Task { await model.accept(s) }
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
            .navigationTitle("Suggestions")
            .refreshable { await model.scanCalendar() }
        }
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
