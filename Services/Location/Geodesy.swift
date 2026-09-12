import Foundation

/// Distances on the sphere, and the local tangent plane used for smoothing and for
/// Ramer–Douglas–Peucker.
enum Geodesy {
    /// WGS84 mean radius. Over a car trip the sphere-vs-ellipsoid error is ~0.2 %, an order
    /// of magnitude below the GPS noise we are fighting, so haversine is the right tool.
    static let earthRadiusMeters = 6_371_008.8
    static let metersPerDegreeLatitude = 111_319.490_793_273_58

    static func distance(
        fromLatitude lat1: Double, longitude lon1: Double,
        toLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = φ2 - φ1
        let dλ = (lon2 - lon1) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2)
            + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        // asin form rather than atan2: identical result, and it keeps the 2·R·asin(√h)
        // shape that makes the antipodal clamp obvious.
        return 2 * earthRadiusMeters * asin(min(1, h.squareRoot()))
    }

    static func distance(from a: LocationSample, to b: LocationSample) -> Double {
        distance(fromLatitude: a.latitude, longitude: a.longitude,
                 toLatitude: b.latitude, longitude: b.longitude)
    }

    /// Equirectangular projection onto a plane tangent at (`originLatitude`,
    /// `originLongitude`), in metres, x east / y north. Valid only close to the origin —
    /// every caller here re-bases it as the vehicle moves.
    static func project(
        latitude: Double, longitude: Double,
        originLatitude: Double, originLongitude: Double
    ) -> (x: Double, y: Double) {
        let y = (latitude - originLatitude) * metersPerDegreeLatitude
        let x = (longitude - originLongitude)
            * metersPerDegreeLatitude * cos(originLatitude * .pi / 180)
        return (x, y)
    }

    static func unproject(
        x: Double, y: Double,
        originLatitude: Double, originLongitude: Double
    ) -> (latitude: Double, longitude: Double) {
        let latitude = originLatitude + y / metersPerDegreeLatitude
        let longitude = originLongitude
            + x / (metersPerDegreeLatitude * cos(originLatitude * .pi / 180))
        return (latitude, longitude)
    }
}
