import Foundation

struct Settings: Codable, Equatable, Sendable {
    /// How many days ahead the heads-up notification fires. 0 turns it off.
    var leadDays = 3
    /// Local hour for notifications and the day-of Live Activity.
    var sendHour = 9
    var includeAnniversaries = true
    var birthdayTemplate = "Happy birthday, {name}!"
    var anniversaryTemplate = "Happy anniversary, {names}!"

    init() {}

    // Tolerates missing keys so new settings don't wipe old installs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        leadDays = try c.decodeIfPresent(Int.self, forKey: .leadDays) ?? d.leadDays
        sendHour = try c.decodeIfPresent(Int.self, forKey: .sendHour) ?? d.sendHour
        includeAnniversaries = try c.decodeIfPresent(Bool.self, forKey: .includeAnniversaries) ?? d.includeAnniversaries
        birthdayTemplate = try c.decodeIfPresent(String.self, forKey: .birthdayTemplate) ?? d.birthdayTemplate
        anniversaryTemplate = try c.decodeIfPresent(String.self, forKey: .anniversaryTemplate) ?? d.anniversaryTemplate
    }
}

/// Everything the app keeps on disk. Contact data is not here: it's re-read
/// from Contacts on every launch, so phone numbers never hit our storage.
struct PersistedState: Codable, Sendable {
    var settings = Settings()
    /// Muted occasion id -> title at the time it was muted (for the unmute list).
    var muted: [String: String] = [:]
    var actions: [ActionRecord] = []
    /// Stats only count occasions from this day on.
    var trackingStart = Date()
    /// Random, identifies this install to the push server.
    var deviceID = UUID().uuidString
    var pushToStartToken: String?
    var lastSyncedHash: String?
    var lastSyncedAt: Date?
    var dismissedSuggestions: Set<String> = []
    /// "occasionID@yyyy-MM-dd" for Live Activities already started locally.
    var startedActivityKeys: Set<String> = []
    /// occasionID -> LiveActivityPlanner key for Live Activities scheduled on iOS 26+.
    var scheduledActivities: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PersistedState()
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? d.settings
        muted = try c.decodeIfPresent([String: String].self, forKey: .muted) ?? [:]
        actions = try c.decodeIfPresent([ActionRecord].self, forKey: .actions) ?? []
        trackingStart = try c.decodeIfPresent(Date.self, forKey: .trackingStart) ?? d.trackingStart
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? d.deviceID
        pushToStartToken = try c.decodeIfPresent(String.self, forKey: .pushToStartToken)
        lastSyncedHash = try c.decodeIfPresent(String.self, forKey: .lastSyncedHash)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        dismissedSuggestions = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedSuggestions) ?? []
        startedActivityKeys = try c.decodeIfPresent(Set<String>.self, forKey: .startedActivityKeys) ?? []
        scheduledActivities = try c.decodeIfPresent([String: String].self, forKey: .scheduledActivities) ?? [:]
    }
}
