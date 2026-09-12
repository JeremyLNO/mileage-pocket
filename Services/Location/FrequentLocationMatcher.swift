import Foundation

/// Learns the places a person keeps arriving at, entirely on this device.
///
/// No model, no server, no inference: a place is "the same place" when it is within a radius
/// of one already seen. That is enough to offer "Client ABC?" after the third visit, and it
/// keeps a log of where someone drives off the network entirely.
enum FrequentLocationMatcher {
    /// 150 m: tight enough not to merge two businesses on the same street, loose enough to
    /// absorb parking round the back and the usual urban GPS error.
    static let defaultRadiusMeters: Double = 150

    static func match(
        latitude: Double,
        longitude: Double,
        in known: [FrequentLocation],
        radiusMeters: Double = defaultRadiusMeters
    ) -> FrequentLocation? {
        known
            .map { (location: $0, distance: Geodesy.distance(
                fromLatitude: latitude, longitude: longitude,
                toLatitude: $0.latitude, longitude: $0.longitude
            )) }
            .filter { $0.distance <= radiusMeters }
            // Nearest wins: two known places inside the radius must not resolve at random.
            .min { $0.distance < $1.distance }?
            .location
    }
}
