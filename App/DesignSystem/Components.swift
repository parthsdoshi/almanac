import SwiftUI

// DESIGN PASS: reusable building blocks. Screens in App/Views are built only
// from these and the tokens in Shared/DesignSystem/Theme.swift.

struct KindBadge: View {
    let kind: OccasionKind

    var body: some View {
        Image(systemName: Theme.Icons.symbol(for: kind))
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Theme.Colors.tint(for: kind), in: Circle())
            .accessibilityLabel(kind.label)
    }
}

struct OccasionRow: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            KindBadge(kind: item.occasion.kind)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.occasion.title)
                    .font(Theme.Typography.rowTitle)
                Text(subtitle)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(countdown)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(item.daysUntil == 0 ? Theme.Colors.tint(for: item.occasion.kind) : .secondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var subtitle: String {
        let date = item.nextDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        guard let years = item.years else { return date }
        switch item.occasion.kind {
        case .birthday: return "\(date) · turns \(years)"
        case .anniversary: return "\(date) · \(years.formatted(.number)) years"
        }
    }

    private var countdown: String {
        switch item.daysUntil {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "\(item.daysUntil)d"
        }
    }
}

struct ActionButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let systemImage: String
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
        .tint(tint)
    }

    private var tint: Color {
        switch style {
        case .primary: Theme.Colors.accent
        case .secondary: .gray
        case .destructive: .red
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.statValue)
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
        .background(Theme.Colors.groupedCardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

struct StatusDot: View {
    let status: OccasionStats.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch status {
        case .acted: Theme.Colors.acted
        case .missed: Theme.Colors.missed
        case .pending: Theme.Colors.pending
        }
    }

    private var label: String {
        switch status {
        case .acted: "Reached out"
        case .missed: "Missed"
        case .pending: "Today"
        }
    }
}
