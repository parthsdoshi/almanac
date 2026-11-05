import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats
        NavigationStack {
            List {
                Section {
                    VStack(spacing: Theme.Spacing.m) {
                        if let rate = stats.actedRate {
                            RateCard(rate: rate)
                        }
                        HStack(spacing: Theme.Spacing.m) {
                            StatTile(value: "\(stats.acted)", label: "Reached out", color: Theme.Colors.acted)
                            StatTile(value: "\(stats.missed)", label: "Missed", color: Theme.Colors.missed)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Eyebrow(text: "Since \(model.store.state.trackingStart.formatted(date: .long, time: .omitted))")
                        .textCase(nil)
                } footer: {
                    Text("Unmuted occasions only. A text counts once Messages reports it sent; a call counts when you open the call prompt.")
                        .foregroundStyle(Theme.Colors.inkSoft)
                }

                if !stats.rows.isEmpty {
                    Section {
                        ForEach(stats.rows) { row in
                            HStack(spacing: Theme.Spacing.m) {
                                StatusDot(status: row.status)
                                Text(row.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.ink)
                                Spacer()
                                Text(dayText(row.day))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.Colors.inkSoft)
                            }
                        }
                        .listRowBackground(Theme.Colors.card)
                    } header: {
                        SectionTitle(title: "History")
                    }
                }
            }
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .navigationTitle("Stats")
        }
    }

    /// "2026-10-30" -> "Oct 30" this year, "Oct 30, 2025" otherwise.
    private func dayText(_ day: DayKey) -> String {
        let parts = day.rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return day.rawValue
        }
        let thisYear = Calendar.current.component(.year, from: .now) == parts[0]
        return thisYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// "You reached out for 78%" with a progress bar and a little confetti.
private struct RateCard: View {
    let rate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text("You reached out for ")
                + Text(rate.formatted(.percent.precision(.fractionLength(0)))).foregroundColor(Theme.Colors.acted))
                .font(Theme.Typography.statHeadline)
                .foregroundStyle(Theme.Colors.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.sunk)
                    Capsule().fill(Theme.Colors.acted).frame(width: geo.size.width * CGFloat(min(max(rate, 0), 1)))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ConfettiField(seed: 5, count: 16).frame(width: 160, height: 90)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .paperCard()
    }
}
