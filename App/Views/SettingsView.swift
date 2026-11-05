import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminders") {
                    Stepper(value: binding(\.leadDays), in: 0...30) {
                        Text(model.settings.leadDays == 0 ? "No heads-up" : "Heads-up \(model.settings.leadDays) day\(model.settings.leadDays == 1 ? "" : "s") before")
                    }
                    Picker("Time", selection: binding(\.sendHour)) {
                        ForEach(5..<23) { hour in
                            Text(Calendar.current.date(from: DateComponents(hour: hour))!.formatted(date: .omitted, time: .shortened))
                                .tag(hour)
                        }
                    }
                    Toggle("Include anniversaries", isOn: binding(\.includeAnniversaries))
                        .tint(Theme.Colors.acted)
                }
                .listRowBackground(Theme.Colors.card)

                Section {
                    TextField("Birthday", text: binding(\.birthdayTemplate), axis: .vertical)
                    TextField("Anniversary", text: binding(\.anniversaryTemplate), axis: .vertical)
                } header: {
                    Text("Message drafts")
                } footer: {
                    Text("{name} is their first name. {names} is both names for a couple.")
                }
                .listRowBackground(Theme.Colors.card)

                Section("Muted") {
                    let muted = model.store.state.muted.sorted { $0.value < $1.value }
                    if muted.isEmpty {
                        Text("Nothing muted").foregroundStyle(Theme.Colors.inkSoft)
                    }
                    ForEach(muted, id: \.key) { entry in
                        HStack {
                            Text(entry.value)
                            Spacer()
                            Button("Unmute") { Task { await model.unmute(occasionID: entry.key) } }
                        }
                    }
                }
                .listRowBackground(Theme.Colors.card)

                Section {
                    LabeledContent("Server", value: model.server.hostDescription)
                    if let synced = model.store.state.lastSyncedAt {
                        LabeledContent("Last sync", value: synced.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let status = model.serverStatus {
                        Text(status).foregroundStyle(Theme.Colors.missed)
                    }
                    if model.server.isConfigured {
                        Button("Sync now") { Task { await model.syncServer(force: true) } }
                        Button("Send a test Live Activity") { Task { await model.sendServerTest() } }
                    }
                    Button("Preview Live Activity on this phone") { model.previewLiveActivity() }
                } header: {
                    Text("Day-of Live Activity")
                } footer: {
                    Text(model.server.isConfigured
                         ? "The server starts the Live Activity at your reminder time, even if the app isn't open. It only has first names and dates."
                         : "No push server is set up, so the Live Activity starts when you open the app on the day.")
                }
                .listRowBackground(Theme.Colors.card)
            }
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .navigationTitle("Settings")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}
