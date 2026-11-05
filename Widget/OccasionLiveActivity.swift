import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// DESIGN PASS: the Lock Screen and Dynamic Island layouts live here. They use
// the same tokens as the app (Shared/DesignSystem/Theme.swift).

struct OccasionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OccasionAttributes.self) { context in
            OccasionLockScreenView(context: context)
                .activityBackgroundTint(Theme.Colors.liveActivityBackground)
                .activitySystemActionForegroundColor(Theme.Colors.liveActivityForeground)
                .widgetURL(DeepLink.url(occasionID: context.attributes.occasionID, action: .open))
        } dynamicIsland: { context in
            let kind = OccasionKind(rawValue: context.attributes.kind) ?? .birthday
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: Theme.Icons.symbol(for: kind))
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.islandTint(for: kind))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline)
                        .font(Theme.Typography.liveHeadline)
                        .foregroundStyle(Theme.Colors.islandForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    OccasionActionRow(occasionID: context.attributes.occasionID, kind: kind, onIsland: true)
                        .background(alignment: .top) {
                            ConfettiField(seed: 17, count: 18).frame(height: 24).offset(y: -30)
                        }
                }
            } compactLeading: {
                Image(systemName: Theme.Icons.symbol(for: kind))
                    .foregroundStyle(Theme.Colors.islandTint(for: kind))
            } compactTrailing: {
                Text(Names.join(context.attributes.names))
                    .font(Theme.Typography.display(15, .black))
                    .foregroundStyle(Theme.Colors.islandForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: Theme.Icons.symbol(for: kind))
                    .foregroundStyle(Theme.Colors.islandTint(for: kind))
            }
            .keylineTint(Theme.Colors.islandTint(for: kind))
            .widgetURL(DeepLink.url(occasionID: context.attributes.occasionID, action: .open))
        }
    }
}

struct OccasionLockScreenView: View {
    let context: ActivityViewContext<OccasionAttributes>

    private var kind: OccasionKind { OccasionKind(rawValue: context.attributes.kind) ?? .birthday }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: Theme.Spacing.m) {
                // The Live Activity only runs on the day, so today's date is the occasion's date.
                DateChip(date: .now, kind: kind)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.headline)
                        .font(Theme.Typography.liveHeadline)
                        .foregroundStyle(Theme.Colors.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.inkSoft)
                }
                Spacer(minLength: 0)
            }
            OccasionActionRow(occasionID: context.attributes.occasionID, kind: kind, onIsland: false)
        }
        .padding(Theme.Spacing.l)
        .background(alignment: .topTrailing) {
            ConfettiField(seed: 11, count: 20).frame(width: 170, height: 70)
        }
    }
}

/// Message and Call open the app (Live Activity links can only open the host
/// app), which then shows the compose sheet or call prompt right away.
/// Mute runs in the background without opening the app.
struct OccasionActionRow: View {
    let occasionID: String
    let kind: OccasionKind
    /// The Dynamic Island is always black, so it gets fixed night colors.
    let onIsland: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Link(destination: DeepLink.url(occasionID: occasionID, action: .message)) {
                LiveActionLabel(title: "Message", systemImage: Theme.Icons.message, style: .primary(kind), onIsland: onIsland)
            }
            Link(destination: DeepLink.url(occasionID: occasionID, action: .call)) {
                LiveActionLabel(title: "Call", systemImage: Theme.Icons.call, style: .quiet, onIsland: onIsland)
            }
            Button(intent: MuteOccasionIntent(occasionID: occasionID)) {
                LiveActionLabel(title: "Mute", systemImage: Theme.Icons.mute, style: .quiet, onIsland: onIsland)
            }
            .buttonStyle(.plain)
        }
    }
}

struct LiveActionLabel: View {
    enum Style { case primary(OccasionKind), quiet }

    let title: String
    let systemImage: String
    let style: Style
    let onIsland: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay {
                if case .quiet = style, !onIsland {
                    RoundedRectangle(cornerRadius: Theme.Radius.button).strokeBorder(Theme.Colors.rule, lineWidth: 1)
                }
            }
    }

    private var foreground: Color {
        switch style {
        case .primary(let kind): onIsland ? Theme.Colors.islandOnAccent : Theme.Colors.onTint(for: kind)
        case .quiet: onIsland ? Theme.Colors.islandForeground : Theme.Colors.ink
        }
    }

    private var background: Color {
        switch style {
        case .primary(let kind): onIsland ? Theme.Colors.islandTint(for: kind) : Theme.Colors.tint(for: kind)
        case .quiet: onIsland ? Theme.Colors.islandButton : Theme.Colors.sunk
        }
    }
}
