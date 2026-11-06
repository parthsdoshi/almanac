import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            StackedPages()
            Text("Never miss a birthday")
                .font(Theme.Typography.display(44, .black, relativeTo: .largeTitle))
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
            Text("Shebang#! reads birthdays and anniversaries from your contacts, reminds you ahead of time, and puts a message or call one tap away on the day.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.inkSoft)
            Spacer()
            if model.contactsAccess == .denied {
                ActionButton(title: "Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Text("Contacts access is off. Turn it on in Settings to continue.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.inkSoft)
            } else {
                ActionButton(title: "Allow Contacts and Notifications", systemImage: "person.crop.circle.badge.checkmark") {
                    Task { await model.requestPermissions() }
                }
                Text("Nothing is sent without your tap.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
        }
        .padding(Theme.Spacing.xl)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.Colors.paper
                ConfettiField(seed: 3, count: 60).frame(height: 420)
            }
            .ignoresSafeArea()
        }
    }
}

/// Three tear-off pages fanned out, the front one with a gift on it.
private struct StackedPages: View {
    var body: some View {
        ZStack {
            page.rotationEffect(.degrees(-9)).offset(x: -10, y: 4)
            page.rotationEffect(.degrees(7)).offset(x: 10)
            VStack(spacing: 0) {
                Text("BIRTHDAY")
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(Theme.Colors.onBirthday)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Theme.Colors.birthday)
                Image(systemName: Theme.Icons.symbol(for: .birthday))
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Colors.birthday)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 140, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .paperCard()
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Colors.card)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.rule, lineWidth: 1))
            .frame(width: 140, height: 156)
    }
}
