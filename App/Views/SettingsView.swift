import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(HealthService.enabledKey) private var saveToHealth = false
    @AppStorage(CloudSync.enabledKey) private var syncICloud = true
    private var cloud: CloudSync { .shared }
    @State private var healthNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScreenHeader(title: "Settings").screenHeaderRow()
                }
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
                    Stepper(value: binding(\.giftLeadDays), in: 0...60) {
                        Text(model.settings.giftLeadDays == 0 ? "No gift reminder" : "Gift reminder \(model.settings.giftLeadDays) day\(model.settings.giftLeadDays == 1 ? "" : "s") before")
                    }
                } header: {
                    Text("Starred people")
                } footer: {
                    Text("Star someone from their page to get a nudge to buy a gift, on top of the usual heads-up.")
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
                    if model.server.isConfigured {
                        LabeledContent("Server", value: model.server.hostDescription)
                    }
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
                         : LiveActivityManager.canSchedule
                            ? "Your phone schedules the next few Live Activities for your reminder time. Opening the app now and then keeps them topped up; anything not scheduled gets a notification instead."
                            : "The Live Activity starts when you open the app on the day. On iOS 26 or later it starts by itself at your reminder time.")
                }
                .listRowBackground(Theme.Colors.card)

                Section {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { syncICloud },
                        set: { syncICloud = $0; cloud.setEnabled($0) }))
                        .tint(Theme.Colors.acted)
                    if syncICloud {
                        if let p = cloud.problem {
                            Text(p).font(.footnote).foregroundStyle(Theme.Colors.missed)
                        } else if let t = cloud.lastSynced {
                            LabeledContent("Last synced", value: t.formatted(date: .omitted, time: .shortened))
                        } else if !CloudSync.canRun {
                            Text("Sync runs on a real iPhone.").font(.footnote).foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Notes, what you know about people, workouts, stars, mutes and these settings stay in step on your devices, in your own iCloud. Birthdays sync through Contacts and to-dos through Reminders already.")
                }
                .listRowBackground(Theme.Colors.card)

                if HealthService.isAvailable {
                    Section {
                        Toggle("Save workouts to Health", isOn: Binding(
                            get: { saveToHealth },
                            set: { on in
                                if !on { saveToHealth = false; healthNote = nil; return }
                                Task {
                                    let ok = await HealthService.shared.requestAccess()
                                    saveToHealth = ok
                                    healthNote = ok ? nil : "Health didn't allow it. Turn on Shebang#! in the Health app under Sharing, then try again."
                                }
                            }))
                            .tint(Theme.Colors.acted)
                        if let healthNote {
                            Text(healthNote).font(.footnote).foregroundStyle(Theme.Colors.missed)
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Each finished lift goes to Health as a strength workout, and bodyweight you log goes in too. Nothing is read from Health.")
                    }
                    .listRowBackground(Theme.Colors.card)
                }

                Section {
                    Button("Show the tour again") { model.showTutorial = true }
                }
                .listRowBackground(Theme.Colors.card)
            }
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .tabScreen("Settings")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}
