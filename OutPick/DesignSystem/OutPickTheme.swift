import SwiftUI
import UIKit

enum OutPickTheme {
    enum ColorToken {
        static let accent = UIColor(red: 0.498, green: 0.859, blue: 0.118, alpha: 1.0)

        static let backgroundBase = UIColor(red: 0.035, green: 0.039, blue: 0.047, alpha: 1.0)
        static let backgroundRaised = UIColor(red: 0.063, green: 0.071, blue: 0.086, alpha: 1.0)
        static let surfaceBase = UIColor(red: 0.086, green: 0.098, blue: 0.122, alpha: 1.0)
        static let surfaceElevated = UIColor(red: 0.118, green: 0.133, blue: 0.165, alpha: 1.0)
        static let surfacePressed = UIColor(red: 0.157, green: 0.176, blue: 0.212, alpha: 1.0)

        static let borderSubtle = UIColor(red: 0.165, green: 0.184, blue: 0.220, alpha: 1.0)
        static let borderStrong = UIColor(red: 0.227, green: 0.255, blue: 0.302, alpha: 1.0)

        static let textPrimary = UIColor(red: 0.957, green: 0.965, blue: 0.973, alpha: 1.0)
        static let textSecondary = UIColor(red: 0.682, green: 0.710, blue: 0.753, alpha: 1.0)
        static let textTertiary = UIColor(red: 0.455, green: 0.490, blue: 0.549, alpha: 1.0)
        static let textDisabled = UIColor(red: 0.314, green: 0.345, blue: 0.400, alpha: 1.0)

        static let iconPrimary = UIColor(red: 0.933, green: 0.945, blue: 0.961, alpha: 1.0)
        static let iconSecondary = UIColor(red: 0.553, green: 0.588, blue: 0.651, alpha: 1.0)
        static let overlayScrim = UIColor.black.withAlphaComponent(0.56)

        static let like = UIColor(red: 1.000, green: 0.294, blue: 0.420, alpha: 1.0)
        static let destructive = UIColor(red: 1.000, green: 0.310, blue: 0.310, alpha: 1.0)
        static let warning = UIColor(red: 1.000, green: 0.690, blue: 0.260, alpha: 1.0)
        static let success = UIColor(red: 0.357, green: 0.859, blue: 0.443, alpha: 1.0)
    }

    enum SwiftUIColor {
        static let accent = Color(uiColor: ColorToken.accent)

        static let backgroundBase = Color(uiColor: ColorToken.backgroundBase)
        static let backgroundRaised = Color(uiColor: ColorToken.backgroundRaised)
        static let surfaceBase = Color(uiColor: ColorToken.surfaceBase)
        static let surfaceElevated = Color(uiColor: ColorToken.surfaceElevated)
        static let surfacePressed = Color(uiColor: ColorToken.surfacePressed)

        static let borderSubtle = Color(uiColor: ColorToken.borderSubtle)
        static let borderStrong = Color(uiColor: ColorToken.borderStrong)

        static let textPrimary = Color(uiColor: ColorToken.textPrimary)
        static let textSecondary = Color(uiColor: ColorToken.textSecondary)
        static let textTertiary = Color(uiColor: ColorToken.textTertiary)
        static let textDisabled = Color(uiColor: ColorToken.textDisabled)

        static let iconPrimary = Color(uiColor: ColorToken.iconPrimary)
        static let iconSecondary = Color(uiColor: ColorToken.iconSecondary)
        static let overlayScrim = Color(uiColor: ColorToken.overlayScrim)

        static let like = Color(uiColor: ColorToken.like)
        static let destructive = Color(uiColor: ColorToken.destructive)
        static let warning = Color(uiColor: ColorToken.warning)
        static let success = Color(uiColor: ColorToken.success)
    }

    @MainActor
    static func applyAppAppearance() {
        UIWindow.appearance().overrideUserInterfaceStyle = .dark

        UIView.appearance().tintColor = ColorToken.accent
        UIControl.appearance().tintColor = ColorToken.accent

        configureNavigationBarAppearance()
        configureTabBarAppearance()
    }

    @MainActor
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ColorToken.backgroundBase
        appearance.shadowColor = ColorToken.borderSubtle
        appearance.titleTextAttributes = [
            .foregroundColor: ColorToken.textPrimary
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: ColorToken.textPrimary
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = ColorToken.accent
    }

    @MainActor
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ColorToken.surfaceBase
        appearance.shadowColor = ColorToken.borderSubtle

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().tintColor = ColorToken.accent
        UITabBar.appearance().unselectedItemTintColor = ColorToken.iconSecondary
    }
}
