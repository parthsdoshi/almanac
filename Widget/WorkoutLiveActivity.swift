import ActivityKit
import SwiftUI
import WidgetKit

// The workout Live Activity: the set you're on, then a rest countdown that runs
// by itself. Same paper, ink and party red as the app.

struct WorkoutLiveActivity: Widget {
    private static let islandGold = Color(uiColor: UIColor(hex: 0xFFC857))

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(Theme.Colors.liveActivityBackground)
                .activitySystemActionForegroundColor(Theme.Colors.liveActivityForeground)
                .widgetURL(URL(string: "occasions://workout"))
        } dynamicIsland: { context in
            let state = context.state
            let resting = state.phase == .rest && !context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Workout \(context.attributes.workout)", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.islandBirthday)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if resting, let range = restRange(state) {
                            Text(timerInterval: range, countsDown: true)
                                .foregroundStyle(Self.islandGold)
                        } else {
                            Text(context.attributes.startedAt, style: .timer)
                                .foregroundStyle(Theme.Colors.islandForeground)
                        }
                    }
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resting ? "Next: \(state.exercise)" : headline(state, context.attributes))
                            .font(Theme.Typography.display(20, .black))
                            .foregroundStyle(Theme.Colors.islandForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(subline(state))
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.islandForeground.opacity(0.7))
                            .lineLimit(1)
                        WorkoutBar(value: state.progress, track: Color.white.opacity(0.18), fill: Self.islandGold)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Theme.Colors.islandBirthday)
            } compactTrailing: {
                if resting, let range = restRange(state) {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Self.islandGold)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 44)
                } else if state.totalSets > 0 {
                    Text("\(state.setNumber)/\(state.totalSets)")
                        .monospacedDigit()
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.Colors.islandForeground)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(resting ? Self.islandGold : Theme.Colors.islandBirthday)
            }
            .keylineTint(Theme.Colors.islandBirthday)
            .widgetURL(URL(string: "occasions://workout"))
        }
    }
}

private func restRange(_ s: WorkoutAttributes.ContentState) -> ClosedRange<Date>? {
    guard let start = s.restStartedAt, let end = s.restEndsAt, end > start else { return nil }
    return start...end
}

private func headline(_ s: WorkoutAttributes.ContentState, _ a: WorkoutAttributes) -> String {
    s.phase == .warmup ? "Warm up for Workout \(a.workout)" : s.exercise
}

private func subline(_ s: WorkoutAttributes.ContentState) -> String {
    if s.phase == .warmup { return "\(s.stepCount) sets today" }
    return s.totalSets > 0 ? "Set \(s.setNumber) of \(s.totalSets) · \(s.detail)" : s.detail
}

struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutAttributes>

    private var state: WorkoutAttributes.ContentState { context.state }

    var body: some View {
        Group {
            if state.phase == .rest {
                rest
            } else {
                work
            }
        }
        .padding(Theme.Spacing.l)
    }

    private var work: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.phase == .warmup ? "Workout \(context.attributes.workout) · Warm up"
                                            : "Workout \(context.attributes.workout) · \(state.setLine)")
                    .font(Theme.Typography.eyebrow)
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Theme.Colors.birthday)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.attributes.startedAt, style: .timer)
                    .font(Theme.Typography.eyebrow)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
            Text(headline(state, context.attributes))
                .font(Theme.Typography.liveHeadline)
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(state.phase == .warmup ? context.attributes.title : state.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.inkSoft)
                .lineLimit(1)
            HStack(spacing: Theme.Spacing.s) {
                WorkoutBar(value: state.progress, track: Theme.Colors.sunk, fill: Theme.Colors.gold)
                Text("\(state.stepsDone) of \(state.stepCount) sets")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            .padding(.top, 8)
        }
    }

    private var rest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rest · Workout \(context.attributes.workout)")
                        .font(Theme.Typography.eyebrow)
                        .textCase(.uppercase)
                        .kerning(1)
                        .foregroundStyle(Theme.Colors.inkSoft)
                    if context.isStale || restRange(state) == nil {
                        Text("Rest's up")
                            .font(Theme.Typography.display(40, .black))
                            .foregroundStyle(Theme.Colors.birthday)
                    } else if let range = restRange(state) {
                        Text(timerInterval: range, countsDown: true)
                            .font(Theme.Typography.display(48, .black))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.ink)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Next · set \(state.setNumber) of \(state.totalSets)")
                        .font(Theme.Typography.eyebrow)
                        .textCase(.uppercase)
                        .kerning(1)
                        .foregroundStyle(Theme.Colors.birthday)
                        .lineLimit(1)
                    Text(state.exercise)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(state.detail.components(separatedBy: " · ").first ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: 170, alignment: .trailing)
            }
            if let range = restRange(state), !context.isStale {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.gold)
            }
        }
    }
}

/// A plain rounded bar, drawn in shapes so it looks the same on the Lock Screen and the island.
struct WorkoutBar: View {
    let value: Double
    let track: Color
    let fill: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}
