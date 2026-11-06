import AppIntents
import CoreLocation
import CoreSpotlight
import Foundation

// What Siri, Shortcuts and Spotlight can see in Shebang#!: your birthdays and
// anniversaries, the people they belong to (with what you've jotted about them),
// and your notes. Everything stays on the phone; Spotlight's index is on-device.

// MARK: Birthdays and anniversaries

@available(iOS 18.0, *)
struct OccasionEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Birthday or anniversary")
    static let defaultQuery = OccasionEntityQuery()

    let id: String
    @Property(title: "Name") var name: String
    @Property(title: "Kind") var kind: String
    @Property(title: "Next date") var nextDate: Date
    @Property(title: "Starred") var starred: Bool

    init(_ item: UpcomingItem) {
        id = item.occasion.id
        name = item.occasion.fullNames
        kind = item.occasion.kind.label
        nextDate = item.nextDate
        starred = item.starred
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kind), \(nextDate.formatted(.dateTime.month(.wide).day()))",
            image: .init(systemName: kind == OccasionKind.anniversary.label ? "heart" : "gift"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.displayName = "\(name)'s \(kind.lowercased())"
        a.contentDescription = nextDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        a.keywords = [kind.lowercased(), "birthday", "anniversary"]
        return a
    }
}

@available(iOS 18.0, *)
struct OccasionEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [OccasionEntity] {
        await EntitySource.upcoming().filter { identifiers.contains($0.occasion.id) }.map(OccasionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [OccasionEntity] {
        await EntitySource.upcoming().filter { $0.matches(string) }.map(OccasionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [OccasionEntity] {
        await EntitySource.upcoming().prefix(10).map(OccasionEntity.init)
    }
}

// MARK: People

@available(iOS 18.0, *)
struct PersonEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Person")
    static let defaultQuery = PersonEntityQuery()

    let id: String
    @Property(title: "Name") var name: String
    @Property(title: "What you've jotted") var notes: [String]
    @Property(title: "Next birthday or anniversary") var nextDate: Date?

    init(person: Person, notes: [String], next: Date?) {
        id = person.contactID
        name = person.fullName
        self.notes = notes
        nextDate = next
    }

    var displayRepresentation: DisplayRepresentation {
        let sub = notes.first ?? nextDate.map { "Next up \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
        return DisplayRepresentation(title: "\(name)", subtitle: "\(sub)", image: .init(systemName: "person.crop.circle"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.displayName = name
        a.contentDescription = notes.joined(separator: "\n")
        return a
    }
}

@available(iOS 18.0, *)
struct PersonEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PersonEntity] {
        await EntitySource.people().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PersonEntity] {
        let q = string.lowercased()
        return await EntitySource.people().filter { p in
            p.name.lowercased().contains(q) || p.notes.contains { $0.lowercased().contains(q) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [PersonEntity] {
        await EntitySource.people().filter { !$0.notes.isEmpty }
    }
}

// MARK: Notes, as journal entries

/// A note from the Notes tab. Uses Apple's journal entry schema, so Apple
/// Intelligence and Siri know it's a dated piece of writing they can search
/// and create.
@available(iOS 18.0, *)
@AppEntity(schema: .journal.entry)
struct NoteEntity: IndexedEntity {
    static let defaultQuery = NoteEntityQuery()

    let id: UUID
    var title: String?
    var message: AttributedString?
    var mediaItems: [IntentFile]
    var entryDate: Date?
    var location: CLPlacemark?

    init(_ note: Note) {
        id = note.id
        title = note.title.isEmpty ? nil : note.title
        message = AttributedString(note.body)
        mediaItems = []
        entryDate = note.created
        location = nil
    }

    var displayRepresentation: DisplayRepresentation {
        let body = message.map { String($0.characters) } ?? ""
        let head = title ?? String(body.prefix(40))
        return DisplayRepresentation(title: "\(head)", subtitle: "\(body.prefix(80))", image: .init(systemName: "note.text"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.displayName = title ?? message.map { String(String($0.characters).prefix(40)) }
        a.contentDescription = message.map { String($0.characters) }
        return a
    }
}

@available(iOS 18.0, *)
struct NoteEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        HubStore.shared.state.notes.filter { identifiers.contains($0.id) }.map(NoteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteEntity] {
        let q = string.lowercased()
        return HubStore.shared.state.notes
            .filter { ($0.title + " " + $0.body + " " + $0.tags.joined(separator: " ")).lowercased().contains(q) }
            .map(NoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteEntity] {
        HubStore.shared.state.notes.prefix(10).map(NoteEntity.init)
    }
}

// MARK: Where the entities come from

@MainActor
enum EntitySource {
    /// Intents can run before the app has read contacts this launch.
    static func upcoming() async -> [UpcomingItem] {
        let model = AppModel.shared
        if model.occasions.isEmpty, model.contactsAccess.canRead { await model.reload() }
        return model.upcoming
    }

    @available(iOS 18.0, *)
    static func people() async -> [PersonEntity] {
        let items = await upcoming()
        let hub = HubStore.shared
        var seen = Set<String>()
        var out: [PersonEntity] = []
        for item in items {
            for p in item.occasion.people where seen.insert(p.contactID).inserted {
                let notes = hub.notes(for: [p.contactID]).map(\.text)
                out.append(PersonEntity(person: p, notes: notes, next: item.nextDate))
            }
        }
        return out
    }
}
