import CoreLocation
import Foundation

/// The recorder's view of the GPS receiver.
///
/// Main-actor isolated on purpose: `CLLocationManager` delivers its callbacks on the queue
/// it was created on, the recorder writes SwiftData, and SwiftData's `ModelContext` is not
/// `Sendable`. Pinning the whole location layer to the main actor removes a class of
/// data races rather than papering over them with locks.
@MainActor
protocol LocationProviding: AnyObject {
    var onSample: ((LocationSample) -> Void)? { get set }
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)? { get set }
    func startUpdates()
    func stopUpdates()
    var authorization: CLAuthorizationStatus { get }
    func requestAlways()
    /// Keeps significant-change monitoring armed **between** trips, so iOS relaunches the
    /// app when the phone starts moving and the CarPlay route can be looked at.
    func setSignificantChangeWatch(_ enabled: Bool)
}

/// The only type in the app that touches `CLLocationManager`.
///
/// Everything downstream speaks `LocationSample`, which is what makes the distance pipeline
/// testable on a machine with no GPS: swap this out for an array.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding {
    var onSample: ((LocationSample) -> Void)?
    /// Fires whenever the authorisation changes, so the app can react to a prompt answered
    /// after recording already started — which is what happens on a user's very first trip.
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    /// Energy: a tighter filter in town where turns matter, a looser one on the motorway
    /// where the road is straight. Spec §4 — kilometre accuracy is never the thing traded.
    private static let cityDistanceFilter: CLLocationDistance = 10
    private static let motorwayDistanceFilter: CLLocationDistance = 25
    private static let cityMaxSpeed: CLLocationSpeed = 30 / 3.6
    private static let motorwayMinSpeed: CLLocationSpeed = 90 / 3.6

    private let manager: CLLocationManager
    private var isUpdating = false
    /// Whether a standing watch was asked for. Held separately from `isUpdating` because the
    /// end of a trip must not take it down: that is the whole point of a *standing* watch.
    private var wantsSignificantChangeWatch = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = Self.cityDistanceFilter
        // iOS pauses updates by itself when it decides you have arrived — at a long red
        // light, for instance — and it does not reliably resume. A mileage log cannot stop
        // recording halfway without telling anyone.
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAlways() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // iOS refuses to jump straight to Always; asking for it first simply does
            // nothing, and the user never sees a prompt at all.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        applyBackgroundUpdates()
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        applySignificantChangeMonitoring()
    }

    /// The one thing Always buys that When In Use does not: if iOS terminates the app
    /// mid-drive — memory pressure, a reboot — a significant change relaunches it, and the
    /// recorder picks the trip back up where it stopped. Without it the drive simply ends
    /// wherever the app was killed, and the user finds out at the next launch.
    ///
    /// Armed during every trip, and — when the driver has asked for automatic starting —
    /// kept armed between them as well, which is what lets iOS relaunch a closed app at the
    /// start of a drive. See `BackgroundWatch` for who decides and what it costs.
    private func applySignificantChangeMonitoring() {
        guard manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func setSignificantChangeWatch(_ enabled: Bool) {
        wantsSignificantChangeWatch = enabled
        if enabled {
            applySignificantChangeMonitoring()
        } else if !isUpdating {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    /// Background delivery works under **When In Use** as well as Always.
    ///
    /// Gating it on `.authorizedAlways` was the bug behind the whole product failing at its
    /// one job: almost nobody grants Always at the first prompt, so almost every trip stopped
    /// counting the moment the screen locked — the timer kept running, the distance did not.
    /// A nine-minute drive recorded 1.9 km.
    ///
    /// With the `location` background mode declared, When In Use plus this flag plus the blue
    /// status indicator is exactly the arrangement a running or cycling tracker uses. Always
    /// buys only relaunch-after-termination, which is a separate feature.
    private func applyBackgroundUpdates() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Setting this without the background mode declared raises; the Info.plist
            // declares it, and this keeps the failure obvious if that ever changes.
            manager.allowsBackgroundLocationUpdates = true
        default:
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        // Only if nobody is standing watch. Taking it down here unconditionally would undo,
        // at the end of every trip, the very thing that lets the next one start by itself.
        if !wantsSignificantChangeWatch {
            manager.stopMonitoringSignificantLocationChanges()
        }
        // Leaving this on keeps the app eligible to wake for location forever, which shows
        // up as battery drain attributed to an app that is doing nothing.
        manager.allowsBackgroundLocationUpdates = false
    }

    private func receive(_ samples: [LocationSample]) {
        for sample in samples {
            onSample?(sample)
            adaptDistanceFilter(to: sample.speed)
        }
    }

    private func authorizationChanged(to status: CLAuthorizationStatus) {
        applyBackgroundUpdates()
        if isUpdating, status == .authorizedAlways || status == .authorizedWhenInUse {
            // Re-issuing is harmless when already running, and it is what actually gets
            // deliveries going when the prompt was answered after `startUpdates()`.
            manager.startUpdatingLocation()
            // Always may have just been granted, mid-trip.
            applySignificantChangeMonitoring()
        }
        // …or granted while no trip is running, which is when the standing watch becomes
        // possible at all: it is delivered under Always and under nothing else.
        if wantsSignificantChangeWatch { applySignificantChangeMonitoring() }
        onAuthorizationChange?(status)
    }

    private func adaptDistanceFilter(to speed: CLLocationSpeed) {
        guard speed >= 0 else { return }
        let wanted: CLLocationDistance
        if speed >= Self.motorwayMinSpeed {
            wanted = Self.motorwayDistanceFilter
        } else if speed <= Self.cityMaxSpeed {
            wanted = Self.cityDistanceFilter
        } else {
            return  // in between: leave it alone rather than flapping on every fix
        }
        if manager.distanceFilter != wanted { manager.distanceFilter = wanted }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // CLLocationManager calls back on the queue it was created on, and this one is
        // created on the main actor, so the isolation being assumed here is real.
        let samples = locations.map(LocationSample.init)
        MainActor.assumeIsolated { receive(samples) }
    }

    /// The first trip of a user's life starts before the prompt is answered. Without this,
    /// the answer arrived and nothing acted on it: background updates stayed off for the
    /// whole trip, and the next launch was the earliest anything could change.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Only the status crosses the boundary; the manager itself is reached through the
        // stored property, which is already main-actor isolated.
        MainActor.assumeIsolated { authorizationChanged(to: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure is normal indoors and in tunnels; the filter already treats a
        // silence as a gap, so there is nothing to do but let it pass.
    }
}
