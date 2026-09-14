import AVFoundation
import Foundation
import UIKit

/// Whether the phone is plugged into a car.
///
/// Read from the audio route rather than from CarPlay's own framework: a CarPlay app needs
/// an entitlement Apple grants to navigation, audio and parking apps, and a mileage log is
/// none of those. The route tells us what we actually need — this phone is in a car that has
/// just been switched on — and it needs no entitlement at all.
///
/// Bluetooth car stereos are deliberately **not** treated as a car: `.bluetoothA2DP` is also
/// a pair of headphones, and starting a trip because someone put their earbuds in is worse
/// than not starting one at all.
///
/// ## What this cannot do
///
/// A suspended app receives no notifications, and iOS does not launch an app for CarPlay
/// unless it declares a CarPlay scene — which needs an entitlement Apple grants to
/// navigation, audio, parking, EV charging and quick-food apps. So this fires when Mileage
/// Pocket is in the foreground, or still alive in the background, and otherwise on the next
/// launch. The settings screen says so rather than letting a driver believe otherwise.
@MainActor
protocol CarConnectionObserving: AnyObject {
    var isConnected: Bool { get }
    /// Fires on every change, with the new state. Never fires for an unchanged route.
    var onChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
    /// Re-reads the route and reports a change if one happened while nobody was listening.
    ///
    /// Route notifications are not delivered to a suspended process and are not replayed on
    /// resume. Without this, a phone plugged in while the app slept came back believing it
    /// was still unplugged — and the driver got no trip, with the feature switched on.
    func refresh()
}

@MainActor
final class CarConnectionMonitor: CarConnectionObserving {
    private(set) var isConnected = false
    var onChange: ((Bool) -> Void)?

    private let session: AVAudioSession
    private var observers: [NSObjectProtocol] = []

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func start() {
        guard observers.isEmpty else { return }
        configureSession()
        isConnected = Self.isCarRoute(session.currentRoute)

        observe(AVAudioSession.routeChangeNotification, object: session)
        // The audio server can restart underneath the app; every session then reverts to its
        // defaults and the route read before it means nothing.
        observe(AVAudioSession.mediaServicesWereResetNotification, object: nil)
        // The one that matters most in practice: nothing is delivered while the process is
        // suspended, so coming back to the foreground is the moment to look again.
        observe(UIApplication.didBecomeActiveNotification, object: nil)
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func refresh() {
        update(to: Self.isCarRoute(session.currentRoute))
    }

    /// A category is set — and never activated — so the session has a real route to report.
    ///
    /// A session that has never been configured answers `currentRoute` with the process's own
    /// default rather than with what the phone is actually plugged into. `.ambient` with
    /// `.mixWithOthers` is the one category that changes nothing for the user: no ducking, no
    /// interruption, nothing stopped. The app plays no audio; it only needs to be told where
    /// the audio would go.
    private func configureSession() {
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func observe(_ name: Notification.Name, object: Any?) {
        let observer = NotificationCenter.default.addObserver(
            forName: name, object: object, queue: .main
        ) { [weak self] _ in
            // The route-change notification carries the *previous* route; the current one is
            // read from the session. Hopping to the main actor keeps the callback on the
            // actor the rest of this type lives on.
            MainActor.assumeIsolated {
                guard let self else { return }
                if name == AVAudioSession.mediaServicesWereResetNotification { self.configureSession() }
                self.refresh()
            }
        }
        observers.append(observer)
    }

    private func update(to connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onChange?(connected)
    }

    /// A CarPlay head unit appears as a `carAudio` output port. USB and Bluetooth ports do
    /// not, which is what keeps a phone charging in a kitchen from looking like a car.
    static func isCarRoute(_ route: AVAudioSessionRouteDescription) -> Bool {
        route.outputs.contains { $0.portType == .carAudio }
    }
}
