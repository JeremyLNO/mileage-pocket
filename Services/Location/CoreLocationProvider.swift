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
    func startUpdates()
    func stopUpdates()
    var authorization: CLAuthorizationStatus { get }
    func requestAlways()
}

/// The only type in the app that touches `CLLocationManager`.
///
/// Everything downstream speaks `LocationSample`, which is what makes the distance pipeline
/// testable on a machine with no GPS: swap this out for an array.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding {
    var onSample: ((LocationSample) -> Void)?

    /// Energy: a tighter filter in town where turns matter, a looser one on the motorway
    /// where the road is straight. Spec §4 — kilometre accuracy is never the thing traded.
    private static let cityDistanceFilter: CLLocationDistance = 10
    private static let motorwayDistanceFilter: CLLocationDistance = 25
    private static let cityMaxSpeed: CLLocationSpeed = 30 / 3.6
    private static let motorwayMinSpeed: CLLocationSpeed = 90 / 3.6

    private let manager: CLLocationManager
    private var isUpdating = false

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
        // Setting this without the `location` background mode raises an exception, so it is
        // set here rather than in init: the Info.plist declares it, and this keeps the
        // failure mode obvious if that ever changes.
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure is normal indoors and in tunnels; the filter already treats a
        // silence as a gap, so there is nothing to do but let it pass.
    }
}
