import SwiftUI
import UIKit

// Reusable almanac building blocks. Screens in App/Views are built from these,
// Shared/DesignSystem/Almanac.swift and the tokens in Shared/DesignSystem/Theme.swift.

struct KindBadge: View {
    let kind: OccasionKind

    var body: some View {
        Image(systemName: Theme.Icons.symbol(for: kind))
            .font(.body)
            .foregroundStyle(Theme.Colors.onTint(for: kind))
            .frame(width: 36, height: 36)
            .background(Theme.Colors.tint(for: kind), in: Circle())
            .accessibilityLabel(kind.label)
    }
}

/// Small caps label above titles: "THURSDAY · NOVEMBER 5".
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.Colors.inkSoft

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.eyebrow)
            .kerning(1.4)
            .foregroundStyle(color)
    }
}

/// The big serif title at the top of a tab, as the first row of its list.
/// Used with `.tabScreen(_:)`, which keeps the navigation bar slim and only
/// shows the title there once this has scrolled away.
struct ScreenHeader: View {
    let title: String
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow { Eyebrow(text: eyebrow) }
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// A header row section for the top of a tab's List or Form.
    @ViewBuilder
    func screenHeaderRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.xs, bottom: 0, trailing: 0))
    }

    /// Slim navigation bar for a tab's root screen. The large title used to
    /// leave a band of empty space above the list, so the title lives in the
    /// list instead (ScreenHeader) and fades into the bar once scrolled past.
    func tabScreen(_ title: String) -> some View {
        modifier(TabScreenChrome(title: title))
    }
}

private struct TabScreenChrome: ViewModifier {
    let title: String
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.Typography.display(18, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.ink)
                        .opacity(scrolled ? 1 : 0)
                        .accessibilityHidden(!scrolled)
                }
            }
            .modifier(ScrollPastHeader(scrolled: $scrolled))
    }
}

private struct ScrollPastHeader: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > 40
            } action: { _, past in
                withAnimation(.easeInOut(duration: 0.15)) { scrolled = past }
            }
        } else {
            content.onAppear { scrolled = true }
        }
    }
}

/// Italic serif section title with a dotted rule running off to the right.
struct SectionTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
            DottedRule()
        }
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

struct DottedRule: View {
    var body: some View {
        Line()
            .stroke(Theme.Colors.rule, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
            .frame(height: 2)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Big serif day count with its unit underneath.
struct Countdown: View {
    let days: Int

    var body: some View {
        VStack(spacing: 3) {
            if days == 0 {
                Text("Today")
                    .font(Theme.Typography.display(18, .black, relativeTo: .headline))
                    .foregroundStyle(Theme.Colors.birthday)
            } else {
                Text("\(days)")
                    .font(Theme.Typography.countdown)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.ink)
                Text(days == 1 ? "DAY" : "DAYS")
                    .font(Theme.Typography.unit)
                    .kerning(1)
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
    }
}

struct OccasionRow: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            DateChip(date: item.nextDate, kind: item.occasion.kind)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.occasion.fullNames)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    if item.starred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.gold)
                            .accessibilityLabel("Starred")
                    }
                }
                Text(OccasionText.subtitle(item))
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundStyle(Theme.Colors.inkSoft)
                if item.possibleDuplicate {
                    Label("Duplicate? From \(OccasionText.sources(item))", systemImage: "square.on.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.missed)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            Countdown(days: item.daysUntil)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

enum OccasionText {
    /// "Wednesday · turns 40", "Monday · 8th anniversary", "Saturday · birthday".
    static func subtitle(_ item: UpcomingItem) -> String {
        let day = item.nextDate.formatted(.dateTime.weekday(.wide))
        return "\(day) · \(detail(item))"
    }

    /// "iCloud", "iCloud and Gmail": the accounts the people's cards are in.
    static func sources(_ item: UpcomingItem) -> String {
        var seen = Set<String>()
        let unique = item.sources.filter { seen.insert($0).inserted }
        return ListFormatter.localizedString(byJoining: unique)
    }

    /// "turns 31", "8th anniversary", "birthday".
    static func detail(_ item: UpcomingItem) -> String {
        switch (item.occasion.kind, item.years) {
        case (.birthday, let y?): return "turns \(y)"
        case (.birthday, nil): return "birthday"
        case (.anniversary, let y?): return "\(ordinal(y)) anniversary"
        case (.anniversary, nil): return "anniversary"
        }
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Today's occasion: a party-colored card with confetti and the two actions.
struct TodayCard: View {
    let item: UpcomingItem
    let onOpen: () -> Void
    let onMessage: () -> Void
    let onCall: () -> Void

    private var kind: OccasionKind { item.occasion.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    DateChip(date: item.nextDate, kind: kind, scale: 1.15, ring: Theme.Colors.onTint(for: kind))
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Eyebrow(text: "Today", color: Theme.Colors.onTint(for: kind))
                        Text(headline)
                            .font(Theme.Typography.heroTitle)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 10) {
                Button(action: onMessage) {
                    Label(item.occasion.people.count > 1 ? "Message them" : "Message", systemImage: Theme.Icons.message)
                }
                .buttonStyle(PillButtonStyle(fill: Theme.Colors.onTint(for: kind), text: Theme.Colors.tint(for: kind)))
                Button(action: onCall) {
                    Label("Call", systemImage: Theme.Icons.call)
                }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.onTint(for: kind), border: Theme.Colors.onTint(for: kind)))
            }
        }
        .foregroundStyle(Theme.Colors.onTint(for: kind))
        .padding(Theme.Spacing.l)
        .background {
            ZStack {
                Theme.Colors.tint(for: kind)
                ConfettiField(seed: 7, count: 34, colors: Theme.Colors.confettiOnBirthday)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero))
    }

    private var headline: String {
        let who = item.occasion.fullNames
        switch (kind, item.years) {
        case (.birthday, let y?): return "\(who) turns \(y)"
        case (.anniversary, let y?): return "\(who): \(y) years"
        default: return Names.headline(kind: kind, names: [who])
        }
    }
}

/// Full-width button. Primary is the party color, secondary is an ink outline,
/// destructive is quiet text (the confirmation dialog carries the weight).
struct ActionButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let systemImage: String
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        switch style {
        case .primary:
            Button(action: action) { Label(title, systemImage: systemImage) }
                .buttonStyle(PillButtonStyle(fill: Theme.Colors.birthday, text: Theme.Colors.onBirthday, height: 52))
        case .secondary:
            Button(action: action) { Label(title, systemImage: systemImage) }
                .buttonStyle(PillButtonStyle(fill: .clear, text: Theme.Colors.ink, border: Theme.Colors.ink, height: 52))
        case .destructive:
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var text: Color
    var border: Color? = nil
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: Theme.Radius.button).strokeBorder(border, lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Plain look, slight dim on press. Any non-default style keeps buttons in a
/// List row separately tappable.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Typography.statValue)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(Theme.Typography.statLabel)
                .kerning(1)
                .foregroundStyle(Theme.Colors.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

struct StatusDot: View {
    let status: OccasionStats.Status

    var body: some View {
        Group {
            switch status {
            case .acted:
                Circle().fill(Theme.Colors.acted)
            case .missed:
                Circle().strokeBorder(Theme.Colors.missed, lineWidth: 2.5)
            case .pending:
                RoundedRectangle(cornerRadius: 3).fill(Theme.Colors.pending).rotationEffect(.degrees(45)).padding(1)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch status {
        case .acted: "Reached out"
        case .missed: "Missed"
        case .pending: "Today"
        }
    }
}

/// "2025 ········ Texted"
struct LedgerRow: View {
    let leading: String
    let trailing: String
    var trailingColor: Color = Theme.Colors.inkSoft

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(leading).foregroundStyle(Theme.Colors.ink)
            DottedRule()
            Text(trailing).fontWeight(.semibold).foregroundStyle(trailingColor)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Card on paper: cream card, hairline border.
    func paperCard(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.Colors.rule, lineWidth: 1))
    }

    /// Paper background behind a List or Form.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Colors.paper)
    }
}

/// A burst of confetti when you reach out. Fires each time `trigger` changes.
struct ConfettiBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var progress: CGFloat = 0
    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiPieceView(piece: piece, colors: Theme.Colors.confetti)
                        .scaleEffect(1.4)
                        .rotationEffect(.degrees(piece.angle + piece.spin * Double(progress)))
                        .position(
                            x: geo.size.width / 2 + (piece.x - 0.5) * geo.size.width * 1.4 * progress,
                            y: geo.size.height * 0.3 + (piece.y - 0.35) * geo.size.height * 1.1 * progress)
                }
            }
            .opacity(visible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in fire(seed: UInt64(truncatingIfNeeded: newValue)) }
    }

    private func fire(seed: UInt64) {
        guard !reduceMotion else { return }
        pieces = ConfettiPiece.scatter(seed: seed &* 7919, count: 90)
        progress = 0
        visible = true
        withAnimation(.easeOut(duration: 1.3)) { progress = 1 }
        withAnimation(.easeIn(duration: 0.4).delay(1.1)) { visible = false }
    }
}
