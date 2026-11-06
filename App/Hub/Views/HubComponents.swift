import SwiftUI

// Pieces the hub screens share, in the same almanac look as Upcoming.

struct TagPill: View {
    let text: String
    var fill: Color = Theme.Colors.sunk
    var color: Color = Theme.Colors.inkSoft

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
    }
}

/// Small caps label with the on-device sparkle: "YOUR DAY".
struct SparkleEyebrow: View {
    let text: String
    var color: Color = Theme.Colors.birthday

    var body: some View {
        Label {
            Text(text.uppercased()).kerning(1.4)
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(Theme.Typography.eyebrow)
        .foregroundStyle(color)
        .labelStyle(.titleAndIcon)
    }
}

/// "Jot anything" field at the top of Today. Tapping opens the capture sheet.
struct CaptureBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.Colors.birthday)
                Text("Jot anything: a to-do, a note, a birthday")
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .paperCard(radius: Theme.Radius.button)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Jot something down")
    }
}

/// Round check box for a to-do.
struct CheckCircle: View {
    let done: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .strokeBorder(done ? Theme.Colors.acted : Theme.Colors.inkSoft, lineWidth: 2)
            .background(done ? Theme.Colors.acted : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(Theme.Colors.card)
                }
            }
            .frame(width: 22, height: 22)
    }
}

struct TodoRow: View {
    let title: String
    let detail: String?
    let done: Bool
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let onToggle {
                Button(action: onToggle) { CheckCircle(done: done) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(done ? "Mark not done" : "Mark done")
            } else {
                CheckCircle(done: done)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .strikethrough(done)
                    .foregroundStyle(done ? Theme.Colors.inkSoft : Theme.Colors.ink)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

/// A card of rows. Put a `HairRule()` between rows.
struct RuledCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
    }
}

struct HairRule: View {
    var body: some View {
        Rectangle().fill(Theme.Colors.rule).frame(height: 1)
    }
}

/// The big serif number between − and + buttons.
struct BigStepper: View {
    let label: String
    let value: String
    var unit: String? = nil
    let minus: () -> Void
    let plus: () -> Void
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Eyebrow(text: label)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                roundButton("minus", action: minus).accessibilityLabel("Less")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Theme.Typography.display(56, .black, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit).font(Theme.Typography.display(22, .bold)).foregroundStyle(Theme.Colors.inkSoft)
                    }
                }
                .foregroundStyle(Theme.Colors.ink)
                Spacer()
                roundButton("plus", action: plus).accessibilityLabel("More")
            }
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
            }
        }
        .padding(Theme.Spacing.l)
        .paperCard()
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(Theme.Colors.ink)
                .frame(width: 54, height: 54)
                .overlay(Circle().strokeBorder(Theme.Colors.ink, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Thin gold progress line.
struct GoldBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.sunk)
                Capsule().fill(Theme.Colors.gold).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

extension Date {
    /// "Today", "Tomorrow", "Mon, Nov 9", with the time when it has one.
    func friendly(withTime: Bool, now: Date = .now) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDate(self, inSameDayAs: now) { day = "Today" }
        else if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(self, inSameDayAs: t) { day = "Tomorrow" }
        else { day = formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        return withTime ? "\(day), \(formatted(date: .omitted, time: .shortened))" : day
    }
}
