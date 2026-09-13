import AVFoundation
import Foundation

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
}

@MainActor
final class CarConnectionMonitor: CarConnectionObserving {
    private(set) var isConnected = false
    var onChange: ((Bool) -> Void)?

    private let session: AVAudioSession
    private var observer: NSObjectProtocol?

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func start() {
        guard observer == nil else { return }
        isConnected = Self.isCarRoute(session.currentRoute)
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            // The notification carries the *previous* route; the current one is read from the
            // session. Hopping to the main actor keeps the callback on the actor the rest of
            // this type lives on.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.update(to: Self.isCarRoute(self.session.currentRoute))
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
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
