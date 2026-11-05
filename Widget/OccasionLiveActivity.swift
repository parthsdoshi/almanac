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
                        .foregroundStyle(Theme.Colors.tint(for: kind))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline)
                        .font(Theme.Typography.liveHeadline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    OccasionActionRow(occasionID: context.attributes.occasionID)
                }
            } compactLeading: {
                Image(systemName: Theme.Icons.symbol(for: kind))
                    .foregroundStyle(Theme.Colors.tint(for: kind))
            } compactTrailing: {
                Text(Names.join(context.attributes.names))
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: Theme.Icons.symbol(for: kind))
                    .foregroundStyle(Theme.Colors.tint(for: kind))
            }
            .widgetURL(DeepLink.url(occasionID: context.attributes.occasionID, action: .open))
        }
    }
}

struct OccasionLockScreenView: View {
    let context: ActivityViewContext<OccasionAttributes>

    private var kind: OccasionKind { OccasionKind(rawValue: context.attributes.kind) ?? .birthday }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: Theme.Icons.symbol(for: kind))
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.tint(for: kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.headline)
                        .font(Theme.Typography.liveHeadline)
                    Text("Today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            OccasionActionRow(occasionID: context.attributes.occasionID)
        }
        .foregroundStyle(Theme.Colors.liveActivityForeground)
        .padding(Theme.Spacing.l)
    }
}

/// Message and Call open the app (Live Activity links can only open the host
/// app), which then shows the compose sheet or call prompt right away.
/// Mute runs in the background without opening the app.
struct OccasionActionRow: View {
    let occasionID: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Link(destination: DeepLink.url(occasionID: occasionID, action: .message)) {
                LiveActionLabel(title: "Message", systemImage: Theme.Icons.message)
            }
            Link(destination: DeepLink.url(occasionID: occasionID, action: .call)) {
                LiveActionLabel(title: "Call", systemImage: Theme.Icons.call)
            }
            Button(intent: MuteOccasionIntent(occasionID: occasionID)) {
                LiveActionLabel(title: "Mute", systemImage: Theme.Icons.mute)
            }
            .buttonStyle(.plain)
        }
    }
}

struct LiveActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }
}
