import SwiftUI
import UIKit

/// PsTotp brand colors, taken from the Android theme (`ui/theme/Color.kt`): warm amber/brown
/// primary on warm cream (light) or warm charcoal (dark) surfaces.
enum Palette {
    static let primary = dynamic(light: 0x8B4513, dark: 0xE8953C)
    static let background = dynamic(light: 0xFCF5EE, dark: 0x2A231E)
    static let onBackground = dynamic(light: 0x4A3728, dark: 0xF5F0EB)
    static let surface = dynamic(light: 0xF5EDE5, dark: 0x352B24)
    static let surfaceVariant = dynamic(light: 0xEDE0D4, dark: 0x2E2720)
    static let onSurfaceVariant = dynamic(light: 0x7A6B5D, dark: 0xB0A196)
    static let outline = dynamic(light: 0xD4C4B0, dark: 0x5C4E43)
    static let error = dynamic(light: 0x8B1A1A, dark: 0xD4453A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    /// From a 0xAARRGGBB value (the format `ServiceBrand` uses).
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}
