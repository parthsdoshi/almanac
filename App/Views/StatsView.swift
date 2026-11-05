import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        StatTile(value: "\(stats.acted)", label: "Reached out", color: Theme.Colors.acted)
                        StatTile(value: "\(stats.missed)", label: "Missed", color: Theme.Colors.missed)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(footer(stats))
                }

                if !stats.rows.isEmpty {
                    Section("History") {
                        ForEach(stats.rows) { row in
                            HStack(spacing: Theme.Spacing.m) {
                                StatusDot(status: row.status)
                                Text(row.title)
                                Spacer()
                                Text(row.day.rawValue)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }

    private func footer(_ stats: OccasionStats) -> String {
        let since = model.store.state.trackingStart.formatted(date: .abbreviated, time: .omitted)
        var text = "Unmuted occasions since \(since). A text counts once Messages reports it sent; a call counts when you open the call prompt."
        if let rate = stats.actedRate {
            text = "You reached out for \(rate.formatted(.percent.precision(.fractionLength(0)))). " + text
        }
        return text
    }
}
