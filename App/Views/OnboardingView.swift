import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: Theme.Icons.symbol(for: .birthday))
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.birthday)
            Text("Never miss a birthday")
                .font(Theme.Typography.screenTitle)
                .multilineTextAlignment(.center)
            Text("Occasions reads birthdays and anniversaries from your contacts, reminds you ahead of time, and puts a message or call one tap away on the day.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if model.contactsAccess == .denied {
                ActionButton(title: "Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Text("Contacts access is off. Turn it on in Settings to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ActionButton(title: "Allow Contacts and Notifications", systemImage: "person.crop.circle.badge.checkmark") {
                    Task { await model.requestPermissions() }
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
