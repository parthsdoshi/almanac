import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widget: who's next, and how many days to go.
/// Reads the snapshot the app writes (Shared/WidgetSnapshot.swift); the
/// countdown moves on at each midnight without the app running.
struct NextOccasionWidget: Widget {
    static let kind = WidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextOccasionProvider()) { entry in
            NextOccasionView(entry: entry)
                .containerBackground(Theme.Colors.paper, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The next birthdays and anniversaries, counting down.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextOccasionEntry: TimelineEntry {
    let date: Date
    let upcoming: [WidgetSnapshot.Upcoming]
    /// False until the app has written a snapshot (not opened yet, or no contacts access).
    let hasSnapshot: Bool
}

struct NextOccasionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextOccasionEntry {
        Self.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (NextOccasionEntry) -> Void) {
        if context.isPreview, WidgetSnapshot.load() == nil {
            completion(Self.sample)
        } else {
            completion(Self.entry(at: .now, snapshot: WidgetSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextOccasionEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Now, then every midnight for a week. The app reloads the timeline whenever it refreshes.
        var dates = [Date.now]
        for n in 1...7 {
            if let d = calendar.date(byAdding: .day, value: n, to: today) { dates.append(d) }
        }
        let entries = dates.map { Self.entry(at: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.last!)))
    }

    static func entry(at date: Date, snapshot: WidgetSnapshot?) -> NextOccasionEntry {
        NextOccasionEntry(
            date: date,
            upcoming: snapshot?.upcoming(from: date, limit: 3) ?? [],
            hasSnapshot: snapshot != nil
        )
    }

    static var sample: NextOccasionEntry {
        let cal = Calendar.current
        let now = Date.now
        func item(_ id: String, _ kind: OccasionKind, _ names: String, inDays n: Int, origin: Int?) -> WidgetSnapshot.Item {
            let d = cal.date(byAdding: .day, value: n, to: now)!
            let c = cal.dateComponents([.month, .day], from: d)
            return .init(id: id, kind: kind, names: names, month: c.month!, day: c.day!, originYear: origin)
        }
        let snap = WidgetSnapshot(items: [
            item("a", .birthday, "Priya", inDays: 3, origin: 1995),
            item("b", .anniversary, "Rohan & Anika", inDays: 12, origin: 2019),
            item("c", .birthday, "Leo", inDays: 20, origin: nil),
        ], writtenAt: now)
        return entry(at: now, snapshot: snap)
    }
}

// MARK: Views

struct NextOccasionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextOccasionEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // Empty states

    private var emptyText: String {
        entry.hasSnapshot ? "No birthdays yet" : "Open Almanac to load birthdays"
    }

    // Small: one big tear-off page.

    @ViewBuilder private var small: some View {
        if let next = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    DateChip(date: next.date, kind: next.item.kind, scale: 1.05)
                    Spacer(minLength: 0)
                    Image(systemName: Theme.Icons.symbol(for: next.item.kind))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.tint(for: next.item.kind))
                }
                Spacer(minLength: 0)
                Text(next.item.names)
                    .font(Theme.Typography.display(19, .black))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(Countdown.phrase(next))
                    .font(Theme.Typography.display(14, .italic))
                    .foregroundStyle(Theme.Colors.tint(for: next.item.kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DeepLink.url(occasionID: next.item.id, action: .open))
        } else {
            empty
        }
    }

    // Medium: the next three.

    @ViewBuilder private var medium: some View {
        if entry.upcoming.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coming up")
                    .font(Theme.Typography.display(15, .italic))
                    .foregroundStyle(Theme.Colors.inkSoft)
                ForEach(entry.upcoming) { u in
                    Link(destination: DeepLink.url(occasionID: u.item.id, action: .open)) {
                        HStack(spacing: 10) {
                            DateChip(date: u.date, kind: u.item.kind, scale: 0.72)
                            Text(u.item.names)
                                .font(Theme.Typography.display(16, .bold))
                                .foregroundStyle(Theme.Colors.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Countdown.short(u.daysUntil))
                                .font(Theme.Typography.display(16, .black))
                                .monospacedDigit()
                                .foregroundStyle(u.daysUntil == 0 ? Theme.Colors.tint(for: u.item.kind) : Theme.Colors.ink)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // Lock Screen

    @ViewBuilder private var rectangular: some View {
        if let next = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 1) {
                Label(next.item.kind.label, systemImage: Theme.Icons.symbol(for: next.item.kind))
                    .font(.caption2.weight(.bold))
                    .widgetAccentable()
                Text(next.item.names)
                    .font(.headline)
                    .lineLimit(1)
                Text(Countdown.phrase(next))
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.url(occasionID: next.item.id, action: .open))
        } else {
            Text(emptyText).font(.caption)
        }
    }

    @ViewBuilder private var inline: some View {
        if let next = entry.upcoming.first {
            Label("\(next.item.names) \(Countdown.short(next.daysUntil).lowercased())",
                  systemImage: Theme.Icons.symbol(for: next.item.kind))
        } else {
            Text(emptyText)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "gift.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.birthday)
            Text(emptyText)
                .font(Theme.Typography.display(14, .bold))
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum Countdown {
    /// "Today", "Tomorrow", "In 12d".
    static func short(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(days)d"
        }
    }

    /// "Turns 31 today", "10th anniversary in 4 days", "Birthday tomorrow".
    static func phrase(_ u: WidgetSnapshot.Upcoming) -> String {
        let what: String
        switch (u.item.kind, u.years) {
        case (.birthday, let y?): what = "Turns \(y)"
        case (.anniversary, let y?): what = "\(ordinal(y)) anniversary"
        case (let k, nil): what = k.label
        }
        switch u.daysUntil {
        case 0: return "\(what) today"
        case 1: return "\(what) tomorrow"
        default: return "\(what) in \(u.daysUntil) days"
        }
    }

    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

#Preview(as: .systemSmall) {
    NextOccasionWidget()
} timeline: {
    NextOccasionProvider.sample
}

#Preview(as: .systemMedium) {
    NextOccasionWidget()
} timeline: {
    NextOccasionProvider.sample
}
