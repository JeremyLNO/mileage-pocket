import Foundation

/// One GPS fix, stripped of CoreLocation.
///
/// The whole distance pipeline speaks this type and nothing else, which is what lets the
/// filter, the compactor and the recorder be tested on a Mac with no device, no simulator
/// location feed and no waiting: a trip becomes an array of values.
struct LocationSample: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Radius of 68 % confidence, in metres, as CoreLocation reports it. Negative means the
    /// fix is invalid — the filter treats that as unusable, never as "perfect".
    let horizontalAccuracy: Double
    let altitude: Double
    /// Metres per second, or a negative value when the receiver cannot tell.
    let speed: Double
    let timestamp: Date

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double = 0,
        speed: Double = -1,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.speed = speed
        self.timestamp = timestamp
    }
}
