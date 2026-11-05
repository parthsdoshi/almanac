import UIKit

/// Navigation and tab bars in the almanac look. SwiftUI has no modifier for
/// the large-title font, so this goes through UIAppearance once at launch.
enum Appearance {
    @MainActor
    static func apply() {
        let ink = Theme.Palette.ink

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = Theme.Palette.paper
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [
            .font: Theme.Typography.uiDisplay(36, .black, textStyle: .largeTitle),
            .foregroundColor: ink,
        ]
        nav.titleTextAttributes = [
            .font: Theme.Typography.uiDisplay(18, .bold, textStyle: .headline),
            .foregroundColor: ink,
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = Theme.Palette.tabBar
        tab.shadowColor = Theme.Palette.rule
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = Theme.Palette.inkSoft
            item.normal.titleTextAttributes = [.foregroundColor: Theme.Palette.inkSoft]
            item.selected.iconColor = Theme.Palette.birthday
            item.selected.titleTextAttributes = [.foregroundColor: Theme.Palette.birthday]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
