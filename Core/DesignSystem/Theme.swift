import SwiftUI

/// Visual direction: **instrument cluster**.
///
/// The app's hero content is a number that changes while you drive, so the whole system is
/// built around making numbers legible and stable: tabular monospaced figures, a dial for
/// the primary control, and a deep ink ground on the one screen used at the wheel.
///
/// Colours are defined once here as dynamic (light/dark) values rather than in the asset
/// catalog, so a palette change is one file and every surface follows.
enum Theme {
    // MARK: - Palette

    /// Signal amber — the brand accent and the only colour allowed on a primary action.
    static let signal = Color(light: 0xE8730A, dark: 0xFF9A2E)
    /// Instrument navy — the dark ground of trip mode and of dark appearance.
    static let ink = Color(light: 0x0D1520, dark: 0x080D15)
    /// Business trips.
    static let business = Color(light: 0x0E8F6E, dark: 0x2BC49A)
    /// Personal trips: deliberately desaturated, so a glance separates them without
    /// competing with the amber.
    static let personal = Color(light: 0x5A6B85, dark: 0x8496B2)

    // MARK: - Surfaces

    static let background = Color(light: 0xF3F5F8, dark: 0x080D15)
    static let surface = Color(light: 0xFFFFFF, dark: 0x141C28)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1C2735)
    static let separator = Color(light: 0xDFE4EC, dark: 0x27313F)

    static let textPrimary = Color(light: 0x0D1520, dark: 0xF2F5F9)
    static let textSecondary = Color(light: 0x5B6779, dark: 0x9AA7B8)

    // MARK: - Metrics

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let cardPadding: CGFloat = 18

    /// The dial's face — honey at the top edge into amber, echoing the app icon so the
    /// button and the icon read as the same object. Kept shallow on purpose: depth comes
    /// from the ring, not the fill.
    static var dialGradient: LinearGradient {
        LinearGradient(
            colors: [Color(light: 0xF7B32B, dark: 0xFFC24A), Color(light: 0xDE6B06, dark: 0xE87A12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func tint(for type: TripType) -> Color {
        type == .business ? business : personal
    }
}

extension Color {
    /// Builds a colour that follows the interface style, from two hex literals.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
