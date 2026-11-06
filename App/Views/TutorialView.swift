import SwiftUI

/// A short swipe-through shown once after you allow Contacts, and again from Settings.
struct TutorialView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "bell.badge.fill", tint: Theme.Colors.birthday,
             title: "A heads-up first",
             body: "You get a reminder a few days before each birthday and anniversary in your contacts, at the time you pick in Settings."),
        Page(id: 1, symbol: "iphone.radiowaves.left.and.right", tint: Theme.Colors.anniversary,
             title: "Then, on the day",
             body: "A Live Activity lands on your Lock Screen with Message and Call buttons. Reach out from there and it counts toward your Stats."),
        Page(id: 2, symbol: "sparkles", tint: Theme.Colors.gold,
             title: "Birthdays hiding in your calendar",
             body: "Suggestions finds birthday events in your calendar that aren't in Contacts yet. Check the event, pick the right person, and add it."),
        Page(id: 3, symbol: "star.fill", tint: Theme.Colors.gold,
             title: "Star the important ones",
             body: "Starred people get an extra nudge to buy a gift. Add the Next up widget to your Home Screen to see who's coming."),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .opacity(page < pages.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.l)

            TabView(selection: $page) {
                ForEach(pages) { p in
                    VStack(spacing: Theme.Spacing.xl) {
                        Spacer(minLength: 0)
                        Image(systemName: p.symbol)
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(Theme.Colors.ink)
                            .frame(width: 128, height: 128)
                            .background(p.tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 32))
                            .rotationEffect(.degrees(p.id.isMultiple(of: 2) ? -4 : 4))
                        Text(p.title)
                            .font(Theme.Typography.display(34, .black, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.Colors.ink)
                            .multilineTextAlignment(.center)
                        Text(p.body)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.inkSoft)
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            ActionButton(title: page < pages.count - 1 ? "Next" : "Let's go", systemImage: page < pages.count - 1 ? "arrow.right" : "checkmark") {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .background {
            ZStack(alignment: .top) {
                Theme.Colors.paper
                ConfettiField(seed: 33, count: 30).frame(height: 220)
            }
            .ignoresSafeArea()
        }
    }
}
