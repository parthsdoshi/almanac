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
                }
                ForEach(model.suggestions) { s in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(s.name).font(Theme.Typography.rowTitle)
                        Text(dateText(s.date)).foregroundStyle(.secondary)
                        HStack {
                            Button(s.contactName.map { "Add to \($0)" } ?? "Create contact") {
                                Task { await model.accept(s) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Dismiss") { model.dismiss(s) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .overlay {
                if !model.hasScannedCalendar {
                    ContentUnavailableView {
                        Label("Birthdays in your calendar", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Find birthday events in your calendar that aren't in your contacts yet.")
                    } actions: {
                        Button(scanning ? "Scanning…" : "Scan calendar") {
                            scanning = true
                            Task { await model.scanCalendar(); scanning = false }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scanning)
                    }
                }
            }
            .navigationTitle("Suggestions")
            .refreshable { await model.scanCalendar() }
        }
    }

    private func dateText(_ date: MonthDay) -> String {
        let d = Calendar.current.date(from: DateComponents(year: 2000, month: date.month, day: date.day)) ?? .now
        return d.formatted(.dateTime.month(.wide).day())
    }
}
