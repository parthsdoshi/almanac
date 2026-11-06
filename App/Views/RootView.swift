import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.contactsAccess.canRead {
                TabView(selection: $model.selectedTab) {
                    UpcomingView()
                        .tabItem { Label("Upcoming", systemImage: "calendar") }
                        .tag(AppModel.Tab.upcoming)
                    StatsView()
                        .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                        .tag(AppModel.Tab.stats)
                    SuggestionsView()
                        .tabItem { Label("Suggestions", systemImage: "sparkles") }
                        .tag(AppModel.Tab.suggestions)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppModel.Tab.settings)
                }
                .overlay { ConfettiBurst(trigger: model.celebrations).ignoresSafeArea() }
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.Colors.accent)
        .sheet(item: $model.composeRequest) { request in
            MessageComposeView(request: request) { result in
                model.didFinishCompose(request, result: result)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Who do you want to call?",
            isPresented: Binding(get: { model.callChoice != nil }, set: { if !$0 { model.callChoice = nil } }),
            presenting: model.callChoice
        ) { choice in
            ForEach(choice.options) { option in
                Button("Call \(option.name)") {
                    model.call(option, occasionID: choice.occasionID, day: choice.instanceDay)
                }
            }
        }
        .alert(
            "Almanac",
            isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}
