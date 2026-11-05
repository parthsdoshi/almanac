import SwiftUI

struct OccasionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let occasionID: String
    @State private var confirmingMute = false

    var body: some View {
        if let item = model.upcoming.first(where: { $0.id == occasionID }) {
            content(item)
        } else {
            ContentUnavailableView("Not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func content(_ item: UpcomingItem) -> some View {
        let o = item.occasion
        return ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.m) {
                    CalendarPage(item: item)
                        .padding(.top, Theme.Spacing.s)
                    Text(o.title)
                        .font(Theme.Typography.detailTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .multilineTextAlignment(.center)
                    if item.years != nil {
                        Text(OccasionText.detail(item))
                            .font(Theme.Typography.pill)
                            .foregroundStyle(Theme.Colors.onGold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Theme.Colors.gold, in: Capsule())
                    }
                    if item.daysUntil > 0 {
                        Text(item.daysUntil == 1 ? "Tomorrow" : "In \(item.daysUntil) days")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.inkSoft)
                    }
                }

                VStack(spacing: Theme.Spacing.m) {
                    ActionButton(title: o.people.count > 1 ? "Message them" : "Message", systemImage: Theme.Icons.message) {
                        model.beginMessage(o)
                    }
                    ActionButton(title: "Call", systemImage: Theme.Icons.call, style: .secondary) {
                        model.beginCall(o)
                    }
                }

                let history = model.actions(for: o.id)
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("History")
                            .font(Theme.Typography.display(20, .bold, relativeTo: .title3))
                            .foregroundStyle(Theme.Colors.ink)
                        ForEach(history, id: \.self) { record in
                            LedgerRow(
                                leading: String(record.instanceDay.rawValue.prefix(4)),
                                trailing: record.kind == .messageSent ? "Texted" : "Called",
                                trailingColor: Theme.Colors.acted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.l)
                    .paperCard()
                }

                ActionButton(title: "Mute forever", systemImage: Theme.Icons.mute, style: .destructive) {
                    confirmingMute = true
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.Colors.paper
                if item.daysUntil == 0 {
                    ConfettiField(seed: 21, count: 46).frame(height: 320)
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Mute \(o.title)?", isPresented: $confirmingMute, titleVisibility: .visible) {
            Button("Mute forever", role: .destructive) {
                Task { await model.mute(occasionID: o.id) }
            }
        } message: {
            Text("No more reminders or Live Activities for this. You can unmute it in Settings.")
        }
    }
}

/// The big tear-off page at the top of the detail screen, stamped "Today!" on the day.
private struct CalendarPage: View {
    let item: UpcomingItem

    private var kind: OccasionKind { item.occasion.kind }

    var body: some View {
        VStack(spacing: 0) {
            Text(item.nextDate.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 13, weight: .heavy))
                .kerning(2)
                .foregroundStyle(Theme.Colors.onTint(for: kind))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Theme.Colors.tint(for: kind))
            Text(item.nextDate.formatted(.dateTime.day()))
                .font(Theme.Typography.display(76, .black, relativeTo: .largeTitle))
                .foregroundStyle(Theme.Colors.ink)
                .frame(maxHeight: .infinity)
            Text(item.nextDate.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.caption.weight(.bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Colors.inkSoft)
                .padding(.bottom, 10)
        }
        .frame(width: 132, height: 150)
        .paperCard()
        .background {
            // Two pages peeking out underneath, like a desk calendar.
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.rule).offset(y: 9).padding(.horizontal, 7)
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.sunk).offset(y: 5).padding(.horizontal, 3)
        }
        .overlay(alignment: .bottomTrailing) {
            if item.daysUntil == 0 {
                Text("Today!")
                    .font(Theme.Typography.display(20, .black))
                    .foregroundStyle(Theme.Colors.birthday)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.birthday, lineWidth: 2.5))
                    .rotationEffect(.degrees(-10))
                    .offset(x: 40, y: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.nextDate.formatted(date: .complete, time: .omitted) + (item.daysUntil == 0 ? ", today" : ""))
    }
}
