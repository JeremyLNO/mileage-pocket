import Foundation
import SwiftData

/// Mirror of the in-flight trip, rewritten on every accepted fix.
///
/// This is what makes a crash or a force-quit survivable: on next launch the recorder finds
/// this row and offers to resume, with the distance already accumulated.
@Model
final class ActiveTripState {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var startedAt: Date = Date()
    var lastUpdatedAt: Date = Date()
    var distanceMeters: Double = 0
    var vehicleID: UUID?
    var lastLatitude: Double?
    var lastLongitude: Double?
    var startLatitude: Double?
    var startLongitude: Double?
    /// Seconds spent in detected stops, excluded from moving time.
    var pausedDuration: TimeInterval = 0

    init(tripID: UUID, startedAt: Date = Date(), vehicleID: UUID? = nil) {
        self.id = UUID()
        self.tripID = tripID
        self.startedAt = startedAt
        self.lastUpdatedAt = startedAt
        self.vehicleID = vehicleID
    }
}
