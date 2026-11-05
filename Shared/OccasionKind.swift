import Foundation

enum OccasionKind: String, Codable, CaseIterable, Sendable {
    case birthday
    case anniversary

    var label: String {
        switch self {
        case .birthday: "Birthday"
        case .anniversary: "Anniversary"
        }
    }
}

enum Names {
    /// "Priya", "Alex & Sam", "Alex, Sam & Jo". The server has the same function
    /// (server/src/payload.js) so push-started headlines match local ones.
    static func join(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " & " + names.last!
        }
    }

    static func headline(kind: OccasionKind, names: [String]) -> String {
        let who = join(names)
        switch kind {
        case .birthday: return "\(who)'s birthday"
        case .anniversary: return "\(who)'s anniversary"
        }
    }
}
