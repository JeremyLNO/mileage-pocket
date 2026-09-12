import Foundation
import SwiftData

/// A single accepted GPS fix belonging to the trip **currently being recorded**.
///
/// These rows are deliberately short-lived: they are the crash-recovery buffer. When the
/// trip stops, `RouteCompactor` folds them into `Trip.encodedRoute` and they are deleted.
@Model
final class LocationPoint {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var timestamp: Date = Date()
    var horizontalAccuracy: Double = 0
    var altitude: Double = 0
    var speed: Double = -1
    /// Cumulative trip distance at this point, so recovery does not have to re-integrate.
    var cumulativeDistanceMeters: Double = 0

    init(
        tripID: UUID,
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double,
        altitude: Double = 0,
        speed: Double = -1,
        cumulativeDistanceMeters: Double = 0
    ) {
        self.id = UUID()
        self.tripID = tripID
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.speed = speed
        self.cumulativeDistanceMeters = cumulativeDistanceMeters
    }
}
