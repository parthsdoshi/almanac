import ActivityKit
import Foundation

/// The Live Activity's data. Compiled into both the app and the widget extension.
///
/// This is a wire contract: the push server builds this exact JSON for
/// push-to-start (see server/src/payload.js). Renaming a property here without
/// changing the server breaks the day-of Live Activity silently.
///
/// Apple decodes push payloads with the default JSON strategies, so keep this
/// to strings, numbers and arrays. A `Date` would decode as seconds since 2001.
struct OccasionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// e.g. "Priya's birthday", "Alex & Sam's anniversary".
        var headline: String
    }

    /// Opaque, stable id of the occasion (see `Occasion.makeID`).
    var occasionID: String
    /// `OccasionKind.rawValue`.
    var kind: String
    /// First names only.
    var names: [String]
}
