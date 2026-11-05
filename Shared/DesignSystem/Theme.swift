import SwiftUI

/// Design tokens shared by the app and the Live Activity.
///
/// DESIGN PASS: this file and App/DesignSystem/Components.swift are where a
/// Claude Design pass lands. Screens only use these tokens and components, so
/// restyling shouldn't need changes in App/Views beyond layout tweaks.
enum Theme {
    enum Colors {
        static let accent = Color.accentColor
        static let birthday = Color.pink
        static let anniversary = Color.purple
        static let acted = Color.green
        static let missed = Color.orange
        static let pending = Color.secondary
        static let cardBackground = Color(.secondarySystemBackground)
        /// Cards that sit on a grouped List (Stats); secondarySystemBackground would match the list's own background.
        static let groupedCardBackground = Color(.secondarySystemGroupedBackground)
        static let liveActivityBackground = Color.black.opacity(0.65)
        static let liveActivityForeground = Color.white

        static func tint(for kind: OccasionKind) -> Color {
            switch kind {
            case .birthday: birthday
            case .anniversary: anniversary
            }
        }
    }

    enum Typography {
        static let screenTitle = Font.largeTitle.weight(.bold)
        static let rowTitle = Font.body.weight(.semibold)
        static let rowSubtitle = Font.subheadline
        static let statValue = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let statLabel = Font.caption.weight(.medium)
        static let liveHeadline = Font.headline
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 14
        static let button: CGFloat = 12
    }

    enum Icons {
        static let message = "message.fill"
        static let call = "phone.fill"
        static let mute = "bell.slash.fill"

        static func symbol(for kind: OccasionKind) -> String {
            switch kind {
            case .birthday: "gift.fill"
            case .anniversary: "heart.fill"
            }
        }
    }
}
