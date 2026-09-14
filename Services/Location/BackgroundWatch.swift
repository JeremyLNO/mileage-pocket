import CoreLocation
import Foundation

/// Whether the app should keep an ear on the phone's movements while no trip is running.
///
/// This is what makes automatic starting work when the app is **closed**. Nothing is
/// delivered to a suspended process, and iOS does not launch an app for CarPlay without an
/// entitlement Apple reserves for navigation and audio apps — so plugging in was noticed
/// only if Mileage Pocket happened to still be alive. Significant-change monitoring is the
/// one wake-up an ordinary app may ask for: iOS relaunches it, in the background, when the
/// phone has genuinely moved, and the app then looks at the audio route and decides.
///
/// It is not free, and the cost is the honest part of the trade: the app appears in the
/// battery report for a wake-up every few hundred metres, drive or no drive. That is why it
/// is tied to the switch that asks for it and to nothing else — a driver who has not asked
/// for automatic trips pays nothing.
enum BackgroundWatch {
    /// - Parameters:
    ///   - autoStartEnabled: the CarPlay automatic-start switch.
    ///   - authorization: what iOS currently allows.
    ///
    /// **Always** is required, and not as a preference: significant-change monitoring is
    /// simply not delivered under When In Use, so arming it there would cost the same and
    /// buy nothing — while letting the settings screen promise something that never happens.
    static func shouldWatch(autoStartEnabled: Bool, authorization: CLAuthorizationStatus) -> Bool {
        autoStartEnabled && authorization == .authorizedAlways
    }
}
