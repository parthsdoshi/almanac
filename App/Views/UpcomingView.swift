import SwiftUI

struct UpcomingView: View {
    @Environment(AppModel.self) private var model

    private struct DaySection: Identifiable {
        let id: String
        let items: [UpcomingItem]
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.upcomingPath) {
            List {
                ForEach(sections) { section in
                    Section(section.id) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item.occasion.id) {
                                OccasionRow(item: item)
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.upcoming.isEmpty {
                    ContentUnavailableView(
                        "No birthdays yet",
                        systemImage: "gift",
                        description: Text("Add birthdays to your contacts, or check Suggestions for ones in your calendar.")
                    )
                }
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: String.self) { id in
                OccasionDetailView(occasionID: id)
            }
            .refreshable { await model.reload() }
        }
    }

    private var sections: [DaySection] {
        let groups: [(String, ClosedRange<Int>)] = [
            ("Today", 0...0), ("This week", 1...7), ("This month", 8...31), ("Later", 32...366),
        ]
        let items = model.upcoming
        return groups.compactMap { title, range in
            let matching = items.filter { range.contains($0.daysUntil) }
            return matching.isEmpty ? nil : DaySection(id: title, items: matching)
        }
    }
}
