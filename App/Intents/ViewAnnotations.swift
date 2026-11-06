import AppIntents
import SwiftUI

// Tells Siri and Apple Intelligence what's on screen ("text her happy birthday",
// "what gift ideas did I save for him?"), and lets iOS 27's App Intents tests
// check it. No-ops before iOS 18.4.

extension View {
    @ViewBuilder
    func annotatesOccasion(_ id: String) -> some View {
        if #available(iOS 18.4, *) {
            appEntityIdentifier(EntityIdentifier(for: OccasionEntity.self, identifier: id))
        } else {
            self
        }
    }

    @ViewBuilder
    func annotatesPerson(_ contactID: String?) -> some View {
        if #available(iOS 18.4, *), let contactID {
            appEntityIdentifier(EntityIdentifier(for: PersonEntity.self, identifier: contactID))
        } else {
            self
        }
    }

    @ViewBuilder
    func annotatesNote(_ id: UUID) -> some View {
        if #available(iOS 18.4, *) {
            appEntityIdentifier(EntityIdentifier(for: NoteEntity.self, identifier: id))
        } else {
            self
        }
    }
}
