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
                VStack(spacing: Theme.Spacing.s) {
                    KindBadge(kind: o.kind).scaleEffect(1.6).padding(Theme.Spacing.m)
                    Text(o.title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(item.nextDate.formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                    if let years = item.years {
                        Text(o.kind == .birthday ? "Turns \(years)" : "\(years) years")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.tint(for: o.kind))
                    }
                }

                VStack(spacing: Theme.Spacing.m) {
                    ActionButton(title: o.people.count > 1 ? "Message them" : "Message", systemImage: Theme.Icons.message) {
                        model.beginMessage(o)
                    }
                    ActionButton(title: "Call", systemImage: Theme.Icons.call, style: .secondary) {
                        model.beginCall(o)
                    }
                    ActionButton(title: "Mute forever", systemImage: Theme.Icons.mute, style: .destructive) {
                        confirmingMute = true
                    }
                }

                let history = model.actions(for: o.id)
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("History").font(.headline)
                        ForEach(history, id: \.self) { record in
                            HStack {
                                Text(record.instanceDay.rawValue.prefix(4))
                                Spacer()
                                Text(record.kind == .messageSent ? "Texted" : "Called")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .background(Theme.Colors.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
            }
            .padding(Theme.Spacing.l)
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
