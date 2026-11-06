import AppIntents
import CoreLocation
import CoreSpotlight
import Foundation

/// "Hey Siri, jot in Shebang": the Jot sheet without opening the app.
/// Several to-dos in one breath become several reminders, each with a guessed due date.
struct JotIntent: AppIntent {
    static let title: LocalizedStringResource = "Jot"
    static let description = IntentDescription(
        "Add to-dos, a note, or something about a person, the same way Jot does in the app. Say several to-dos at once to add them all.")

    @Parameter(title: "What to jot", requestValueDialog: "What should I jot down?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Jot \(\.$text)")
    }

    init() {}
    init(text: String) { self.text = text }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let filed = try await JotFiler.file(text)
        return .result(value: filed.summary, dialog: "\(filed.summary)")
    }
}

/// Apple's "create a journal entry" schema, so Apple Intelligence can save a
/// note into Shebang#! when you ask it to.
@available(iOS 18.0, *)
@AppIntent(schema: .journal.createEntry)
struct CreateNoteIntent: AppIntent {
    var message: AttributedString
    var title: String?
    var entryDate: Date?
    var location: CLPlacemark?
    var mediaItems: [IntentFile]

    @MainActor
    func perform() async throws -> some ReturnsValue<NoteEntity> {
        let body = String(message.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = HubStore.shared.addNote(title: title ?? "", body: body)
        EntityIndexer.shared.indexSoon()
        return .result(value: NoteEntity(note))
    }
}

struct ShebangShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: JotIntent(),
            phrases: [
                "Jot in \(.applicationName)",
                "Jot something down in \(.applicationName)",
                "Add to-dos in \(.applicationName)",
            ],
            shortTitle: "Jot",
            systemImageName: "square.and.pencil")
    }
}

/// Keeps Spotlight's on-device index (and with it Siri and Apple Intelligence)
/// in step with your birthdays, people and notes.
@MainActor
final class EntityIndexer {
    static let shared = EntityIndexer()
    private var pending: Task<Void, Never>?

    /// Debounced, so a burst of edits indexes once.
    func indexSoon() {
        guard #available(iOS 18.0, *) else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await indexAll()
        }
    }

    @available(iOS 18.0, *)
    func indexAll() async {
        let index = CSSearchableIndex.default()
        let occasions = AppModel.shared.upcoming.map(OccasionEntity.init)
        let people = await EntitySource.people()
        let notes = HubStore.shared.state.notes.map(NoteEntity.init)
        // Replace, so deleted notes and muted birthdays drop out of Spotlight.
        try? await index.deleteAppEntities(ofType: OccasionEntity.self)
        try? await index.deleteAppEntities(ofType: PersonEntity.self)
        try? await index.deleteAppEntities(ofType: NoteEntity.self)
        try? await index.indexAppEntities(occasions)
        try? await index.indexAppEntities(people)
        try? await index.indexAppEntities(notes)
    }
}
