import Foundation
import UIKit
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

/// Crazy Bee Labs announcements and app-update notices, delivered through OneSignal.
///
/// Config-gated on purpose: with `appID` empty the SDK is never initialised and the
/// app behaves exactly as it did before — no registration, no network call, no prompt.
/// Any reminder the app schedules for itself stays a *local* notification and never
/// goes through here.
///
/// This is the only file in the app that touches the OneSignal SDK, per OneSignal's
/// own integration guidance.
enum OneSignalPush {
    /// OneSignal App ID — onesignal.com ▸ Settings ▸ Keys & IDs. Empty = push disabled.
    static let appID = ""

    static var isConfigured: Bool { !appID.isEmpty }

    /// Retained for the lifetime of the process: `addClickListener` does not keep the
    /// listener alive, so a locally-scoped instance would be deallocated immediately
    /// and taps on a notification would silently do nothing.
    ///
    /// `nonisolated(unsafe)` rather than an actor annotation: the only write happens in
    /// `start()`, called once from the app's `init` on the main actor, and nothing ever
    /// reads it back. Isolating the enum itself would put `ClickListener.onClick` on the
    /// main actor, which cannot satisfy OneSignal's nonisolated protocol requirement.
    private nonisolated(unsafe) static var clickListener: AnyObject?

    /// Call once at launch. Initialising does **not** show the system permission
    /// prompt — OneSignal only completes the device registration when notification
    /// permission has already been granted. Call `promptForPermission()` from an
    /// explicit user opt-in to ask for it.
    static func start() {
        guard isConfigured else { return }
        #if canImport(OneSignalFramework)
        OneSignal.Debug.setLogLevel(.LL_WARN)
        OneSignal.initialize(appID, withLaunchOptions: nil)
        let listener = ClickListener()
        clickListener = listener
        OneSignal.Notifications.addClickListener(listener)
        #endif
    }

    /// Asks for push permission, but only while the choice is still undetermined:
    /// once the user has answered, iOS never re-shows its own dialog and OneSignal
    /// would substitute an app-presented "open Settings" alert instead.
    static func promptForPermission() {
        guard isConfigured else { return }
        #if canImport(OneSignalFramework)
        guard OneSignal.Notifications.permissionNative == .notDetermined else { return }
        OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
        #endif
    }

    /// Opt the device in or out of Crazy Bee Labs pushes without touching the iOS
    /// permission itself — the switch a Settings toggle should drive.
    static func setOptedIn(_ optedIn: Bool) {
        guard isConfigured else { return }
        #if canImport(OneSignalFramework)
        if optedIn {
            OneSignal.User.pushSubscription.optIn()
        } else {
            OneSignal.User.pushSubscription.optOut()
        }
        #endif
    }

    #if canImport(OneSignalFramework)
    /// A push payload is untrusted input, so a tap can only ever open an
    /// allow-listed Crazy Bee Labs or App Store link — never an arbitrary URL.
    private final class ClickListener: NSObject, OSNotificationClickListener {
        private static let allowedHosts: Set<String> = [
            "apps.apple.com", "crazybeelabs.com", "www.crazybeelabs.com",
        ]

        func onClick(event: OSNotificationClickEvent) {
            guard let raw = event.notification.additionalData?["url"] as? String,
                  let url = URL(string: raw),
                  url.scheme == "https",
                  let host = url.host()?.lowercased(),
                  Self.allowedHosts.contains(host)
            else { return }
            Task { @MainActor in UIApplication.shared.open(url) }
        }
    }
    #endif
}
