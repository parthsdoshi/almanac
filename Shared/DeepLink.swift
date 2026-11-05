import Foundation

/// URLs the Live Activity uses to hand off to the app:
/// `occasions://occasion/<id>/<action>`.
///
/// Live Activity links can only open the host app, not Messages or Phone, so
/// Message and Call come into the app first and the app opens the compose
/// sheet or the call prompt immediately.
enum DeepLink {
    static let scheme = "occasions"

    enum Action: String, Sendable {
        case open, message, call
    }

    static func url(occasionID: String, action: Action) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "occasion"
        c.path = "/\(occasionID)/\(action.rawValue)"
        return c.url!
    }

    static func parse(_ url: URL) -> (occasionID: String, action: Action)? {
        guard url.scheme == scheme, url.host == "occasion" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, !parts[0].isEmpty, let action = Action(rawValue: parts[1]) else { return nil }
        return (parts[0], action)
    }
}
