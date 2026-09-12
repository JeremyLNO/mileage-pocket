import CoreLocation
import Foundation

extension LocationSample {
    /// The one place CoreLocation crosses into the distance pipeline.
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            speed: location.speed,
            timestamp: location.timestamp
        )
    }
}
