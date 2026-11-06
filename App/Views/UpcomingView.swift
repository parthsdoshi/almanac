import SwiftUI

struct UpcomingView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var query = ""
    @State private var showingStats = false
    @State private var showingSuggestions = false

    private struct DaySection: Identifiable {
        let id: String
        let items: [UpcomingItem]
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.upcomingPath) {
            List {
                Section {
                    ScreenHeader(
                        title: "Upcoming",
                        eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).replacingOccurrences(of: ",", with: " ·"))
                        .screenHeaderRow()
                }

                if query.isEmpty {
                    Section {
                        Button { showingSuggestions = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "gift.fill").foregroundStyle(Theme.Colors.missed)
                                Text(suggestionsLine)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Colors.inkSoft)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .listRowBackground(Theme.Colors.card)
                    }
                }

                ForEach(sections) { section in
                    if section.id == "Today" {
                        Section {
                            ForEach(section.items) { item in
                                TodayCard(
                                    item: item,
                                    onOpen: { model.upcomingPath.append(item.occasion.id) },
                                    onMessage: { model.beginMessage(item.occasion) },
                                    onCall: { model.beginCall(item.occasion) })
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
                                .modifier(RowSwipeActions(item: item))
                            }
                        }
                    } else {
                        Section {
                            ForEach(section.items) { item in
                                NavigationLink(value: item.occasion.id) {
                                    OccasionRow(item: item)
                                }
                                .modifier(RowSwipeActions(item: item))
                            }
                            .listRowBackground(Theme.Colors.card)
                        } header: {
                            SectionTitle(title: section.id)
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .listRowSeparatorTint(Theme.Colors.rule)
            .paperBackground()
            .overlay {
                if !query.isEmpty && sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if model.upcoming.isEmpty {
                    ContentUnavailableView(
                        "No birthdays yet",
                        systemImage: "gift",
                        description: Text("Add birthdays to your contacts, or find ones in your calendar above.")
                    )
                    .foregroundStyle(Theme.Colors.inkSoft)
                }
            }
            .tabScreen("Upcoming")
            .searchable(text: $query, prompt: "Names, months, dates")
            .navigationDestination(for: String.self) { id in
                OccasionDetailView(occasionID: id)
            }
            .refreshable { await model.reload() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingStats = true } label: { Image(systemName: "chart.bar.fill") }
                        .accessibilityLabel("Stats")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a birthday or anniversary")
                }
            }
            .sheet(isPresented: $adding) { AddOccasionView() }
            .sheet(isPresented: $showingStats) { StatsView().presentationDragIndicator(.visible) }
            .sheet(isPresented: $showingSuggestions) { SuggestionsView().presentationDragIndicator(.visible) }
            .task {
                if CalendarScanner.hasAccess, !model.hasScannedCalendar { await model.scanCalendar() }
            }
            .safeAreaInset(edge: .bottom) {
                if let muted = model.justMuted {
                    HStack {
                        Text("Muted \(muted.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.ink)
                            .lineLimit(1)
                        Spacer()
                        Button("Undo") { Task { await model.unmute(occasionID: muted.id) } }
                            .font(.subheadline.weight(.bold))
                            .tint(Theme.Colors.accent)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                    .paperCard(radius: Theme.Radius.button)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.justMuted?.id)
        }
    }

    private var suggestionsLine: String {
        guard model.hasScannedCalendar else { return "Find birthdays in your calendar" }
        switch model.suggestions.count {
        case 0: return "Your calendar's birthdays are all in Contacts"
        case 1: return "1 birthday found in your calendar"
        case let n: return "\(n) birthdays found in your calendar"
        }
    }

    private var sections: [DaySection] {
        let groups: [(String, ClosedRange<Int>)] = [
            ("Today", 0...0), ("This week", 1...7), ("This month", 8...31), ("Later", 32...366),
        ]
        let items = query.isEmpty ? model.upcoming : model.upcoming.filter { $0.matches(query) }
        return groups.compactMap { title, range in
            let matching = items.filter { range.contains($0.daysUntil) }
            return matching.isEmpty ? nil : DaySection(id: title, items: matching)
        }
    }
}

/// Swipe left to mute (Upcoming shows Undo), swipe right to star.
private struct RowSwipeActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: UpcomingItem

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await model.mute(occasionID: item.occasion.id) }
                } label: {
                    Label("Mute", systemImage: Theme.Icons.mute)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    model.toggleStar(item.occasion.id)
                } label: {
                    Label(item.starred ? "Unstar" : "Star", systemImage: item.starred ? "star.slash" : "star.fill")
                }
                .tint(Theme.Colors.gold)
            }
    }
}
