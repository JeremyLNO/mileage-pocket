import SwiftUI

/// Visual direction: **instrument cluster**.
///
/// The app's hero content is a number that changes while you drive, so the whole system is
/// built around making numbers legible and stable: tabular monospaced figures, a dial for
/// the primary control, and a deep ink ground on the one screen used at the wheel.
///
/// Colours are defined once here as dynamic (light/dark) values rather than in the asset
/// catalog, so a palette change is one file and every surface follows.
///
/// In `Shared/` rather than `Core/DesignSystem/` because the widget extension is a second
/// process that draws the same product. It used to pick its own greys and reds, which is how
/// a home screen ends up looking like a different app than the one it opens.
enum Theme {
    // MARK: - Palette

    /// Signal amber — the brand accent and the only colour allowed on a primary action.
    ///
    /// The light value is deeper than the icon's amber on purpose. This colour is used as
    /// *text* — the eyebrow labels, the tint on every button and on the tab bar — and the
    /// brighter original measured 3.05:1 against white, well under the 4.5:1 WCAG asks of
    /// body text. At 5.1:1 it still reads as the same amber, and white on it (the START
    /// button) gains the same margin. The dial keeps the bright gradient: it is a large
    /// filled object, not text.
    static let signal = Color(light: 0xB05304, dark: 0xFF9A2E)
    /// What a label on a `signal` fill is drawn in.
    ///
    /// It cannot be white in both appearances: the dark-mode amber is bright, and white on it
    /// measures 2.1:1 — the START button, the biggest control in the app, was the least
    /// readable text in it. Dark ink on that amber gives 8.7:1, which is also how iOS draws
    /// a label on its own bright accents.
    static let onSignal = Color(light: 0xFFFFFF, dark: 0x0D1520)

    /// STOP. A fixed red rather than `Color.red`: the system red is tuned to be *seen*, not
    /// to carry white text — it measures 3.5:1 under a white label, and this is the one
    /// control pressed without looking.
    static let stop = Color(light: 0xC2181B, dark: 0xC2181B)

    /// Instrument navy — the dark ground of trip mode and of dark appearance.
    static let ink = Color(light: 0x0D1520, dark: 0x080D15)
    /// Business trips. Darkened for the same reason as `signal`: it labels a pill, and at
    /// the original value it measured 4.06:1 against white.
    static let business = Color(light: 0x0A7A5D, dark: 0x2BC49A)
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
    /// The two stops, named so the contrast test can measure the label against the *lighter*
    /// one — where a label is hardest to read, and where "START" in white measured 1.84:1.
    static let dialHoney = Color(light: 0xF7B32B, dark: 0xFFC24A)
    static let dialAmber = Color(light: 0xDE6B06, dark: 0xE87A12)

    static var dialGradient: LinearGradient {
        LinearGradient(
            colors: [dialHoney, dialAmber],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The dial's own label. Dark ink, for the same reason as `onSignal`: white on this
    /// gradient was the least readable text in the app, on its most important control.
    static let onDial = Color(light: 0x0D1520, dark: 0x0D1520)

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
