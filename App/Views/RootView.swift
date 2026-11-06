import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(HubStore.self) private var hub
    @Environment(WorkoutUI.self) private var workouts

    var body: some View {
        @Bindable var model = model
        Group {
            if model.contactsAccess.canRead {
                TabView(selection: $model.selectedTab) {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "sun.max.fill") }
                        .tag(AppModel.Tab.today)
                    UpcomingView()
                        .tabItem { Label("Upcoming", systemImage: "calendar") }
                        .tag(AppModel.Tab.upcoming)
                    WorkoutsView()
                        .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }
                        .tag(AppModel.Tab.workouts)
                    NotesView()
                        .tabItem { Label("Notes", systemImage: "note.text") }
                        .tag(AppModel.Tab.notes)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppModel.Tab.settings)
                }
                .fullScreenCover(isPresented: Binding(get: { workouts.isPresented }, set: { _ in })) {
                    WorkoutCover()
                        .environment(model)
                        .environment(hub)
                        .environment(workouts)
                }
                .overlay { ConfettiBurst(trigger: model.celebrations).ignoresSafeArea() }
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.Colors.accent)
        .fullScreenCover(isPresented: Binding(
            get: { model.tutorialPresented },
            set: { if !$0 { model.finishTutorial() } }
        )) {
            TutorialView { model.finishTutorial() }
        }
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
            "Shebang#!",
            isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}
