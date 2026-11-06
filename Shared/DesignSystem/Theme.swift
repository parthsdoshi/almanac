import SwiftUI
import UIKit

/// Design tokens shared by the app and the Live Activity: the "almanac" look.
///
/// Cream paper by day, warm ink by night, a chunky soft serif for names and
/// numbers, tear-off calendar dates and party-colored accents. Every color has
/// a light and a dark value, so screens never pick colors themselves.
///
/// This file is the single source of tokens. Screens use these and the
/// components in App/DesignSystem and Shared/DesignSystem/Almanac.swift.
enum Theme {
    /// UIKit colors are the source of truth so the same dynamic color can feed
    /// both SwiftUI and UIAppearance (navigation and tab bars).
    enum Palette {
        static let paper = UIColor(light: 0xF8F0DF, dark: 0x17120E)
        static let card = UIColor(light: 0xFFFAF0, dark: 0x241C16)
        static let sunk = UIColor(light: 0xEFE3CB, dark: 0x2E241C)
        static let rule = UIColor(light: 0xE3D3B4, dark: 0x3A2E24)
        static let tabBar = UIColor(light: 0xFBF5E8, dark: 0x1C1611)
        static let ink = UIColor(light: 0x2B2118, dark: 0xF6ECDC)
        static let inkSoft = UIColor(light: 0x6E5C49, dark: 0xBBA88F)
        static let birthday = UIColor(light: 0xB8322A, dark: 0xFF7A5C)
        static let onBirthday = UIColor(light: 0xFFF8EC, dark: 0x1C110C)
        static let anniversary = UIColor(light: 0x73398F, dark: 0xCFA3EE)
        static let onAnniversary = UIColor(light: 0xFFF8EC, dark: 0x1C110C)
        static let gold = UIColor(light: 0xF2B33D, dark: 0xFFC857)
        static let onGold = UIColor(light: 0x2B2118, dark: 0x1C110C)
        /// Gold on an ink background. Ink turns cream in dark mode, so the gold deepens to stay readable.
        static let goldOnInk = UIColor(light: 0xF2B33D, dark: 0x9A5B00)
        static let acted = UIColor(light: 0x2F7A45, dark: 0x7CCB90)
        static let missed = UIColor(light: 0xA65A0C, dark: 0xF2A54E)
    }

    enum Colors {
        static let paper = Color(uiColor: Palette.paper)
        static let card = Color(uiColor: Palette.card)
        static let sunk = Color(uiColor: Palette.sunk)
        static let rule = Color(uiColor: Palette.rule)
        static let tabBar = Color(uiColor: Palette.tabBar)
        static let ink = Color(uiColor: Palette.ink)
        static let inkSoft = Color(uiColor: Palette.inkSoft)

        static let birthday = Color(uiColor: Palette.birthday)
        static let onBirthday = Color(uiColor: Palette.onBirthday)
        static let anniversary = Color(uiColor: Palette.anniversary)
        static let onAnniversary = Color(uiColor: Palette.onAnniversary)
        static let gold = Color(uiColor: Palette.gold)
        static let onGold = Color(uiColor: Palette.onGold)
        static let goldOnInk = Color(uiColor: Palette.goldOnInk)

        static let accent = birthday
        static let acted = Color(uiColor: Palette.acted)
        static let missed = Color(uiColor: Palette.missed)
        static let pending = gold

        static let cardBackground = card
        static let groupedCardBackground = card

        /// Confetti, light and dark.
        static let confetti: [Color] = [
            Color(uiColor: UIColor(light: 0xE0533D, dark: 0xFF7A5C)),
            Color(uiColor: UIColor(light: 0xF2B33D, dark: 0xFFC857)),
            Color(uiColor: UIColor(light: 0x3D8FC9, dark: 0x6DB3E8)),
            Color(uiColor: UIColor(light: 0xE36FA0, dark: 0xF28DBA)),
            Color(uiColor: UIColor(light: 0x4FA36B, dark: 0x7CCB90)),
        ]
        /// Confetti that sits on a birthday-colored card.
        static let confettiOnBirthday: [Color] = [
            gold, onBirthday,
            Color(uiColor: UIColor(light: 0xF28DBA, dark: 0x8A1E3C)),
            Color(uiColor: UIColor(light: 0x6DB3E8, dark: 0x1E4E7A)),
        ]

        // Live Activity. The Lock Screen follows light/dark; the Dynamic Island is always black.
        static let liveActivityBackground = paper
        static let liveActivityForeground = ink
        static let islandForeground = Color.white
        static let islandButton = Color.white.opacity(0.16)
        static let islandBirthday = Color(uiColor: UIColor(hex: 0xFF7A5C))
        static let islandAnniversary = Color(uiColor: UIColor(hex: 0xCFA3EE))
        static let islandOnAccent = Color(uiColor: UIColor(hex: 0x1C110C))

        static func tint(for kind: OccasionKind) -> Color {
            switch kind {
            case .birthday: birthday
            case .anniversary: anniversary
            }
        }

        static func onTint(for kind: OccasionKind) -> Color {
            switch kind {
            case .birthday: onBirthday
            case .anniversary: onAnniversary
            }
        }

        static func islandTint(for kind: OccasionKind) -> Color {
            switch kind {
            case .birthday: islandBirthday
            case .anniversary: islandAnniversary
            }
        }
    }

    enum Typography {
        /// The display serif: Fraunces (SIL OFL), cut to three static styles in
        /// Shared/Fonts under the family name "Almanac Display". If the font
        /// isn't registered, falls back to the system serif (New York).
        enum Face: String {
            case black = "AlmanacDisplay-Black"
            case bold = "AlmanacDisplay-Bold"
            case italic = "AlmanacDisplay-SemiBoldItalic"

            var fallbackWeight: Font.Weight {
                switch self {
                case .black: .black
                case .bold: .bold
                case .italic: .semibold
                }
            }

            var fallbackUIWeight: UIFont.Weight {
                switch self {
                case .black: .black
                case .bold: .bold
                case .italic: .semibold
                }
            }
        }

        static func display(_ size: CGFloat, _ face: Face = .black, relativeTo style: Font.TextStyle = .body) -> Font {
            if UIFont(name: face.rawValue, size: size) != nil {
                return .custom(face.rawValue, size: size, relativeTo: style)
            }
            let font = Font.system(size: size, weight: face.fallbackWeight, design: .serif)
            return face == .italic ? font.italic() : font
        }

        /// UIKit version for the navigation bar, scaled with Dynamic Type.
        static func uiDisplay(_ size: CGFloat, _ face: Face = .black, textStyle: UIFont.TextStyle = .body) -> UIFont {
            let base: UIFont
            if let custom = UIFont(name: face.rawValue, size: size) {
                base = custom
            } else {
                let system = UIFont.systemFont(ofSize: size, weight: face.fallbackUIWeight)
                var descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
                if face == .italic, let italic = descriptor.withSymbolicTraits(.traitItalic) { descriptor = italic }
                base = UIFont(descriptor: descriptor, size: size)
            }
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        }

        static let screenTitle = display(40, .black, relativeTo: .largeTitle)
        static let heroTitle = display(30, .black, relativeTo: .title)
        static let detailTitle = display(36, .black, relativeTo: .largeTitle)
        static let sectionTitle = display(20, .italic, relativeTo: .title3)
        static let rowTitle = display(18, .bold, relativeTo: .headline)
        static let rowSubtitle = Font.subheadline
        static let countdown = display(28, .black, relativeTo: .title)
        static let unit = Font.caption2.weight(.bold)
        static let eyebrow = Font.caption.weight(.bold)
        static let pill = display(17, .italic, relativeTo: .headline)
        static let statValue = display(52, .black, relativeTo: .largeTitle)
        static let statLabel = Font.caption.weight(.bold)
        static let statHeadline = display(26, .bold, relativeTo: .title2)
        static let button = Font.headline
        static let liveHeadline = display(22, .black, relativeTo: .title3)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let chip: CGFloat = 8
        static let card: CGFloat = 16
        static let hero: CGFloat = 20
        static let button: CGFloat = 14
        static let liveActivity: CGFloat = 24
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// A color that switches with light and dark mode.
    convenience init(light: UInt32, dark: UInt32) {
        let l = UIColor(hex: light), d = UIColor(hex: dark)
        self.init { $0.userInterfaceStyle == .dark ? d : l }
    }
}
