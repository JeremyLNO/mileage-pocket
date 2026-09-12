import Foundation
import SwiftData

/// A place the user keeps arriving at, learned purely on-device from trip endpoints.
@Model
final class FrequentLocation {
    var id: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var address: String?
    var label: String?
    var clientID: UUID?
    var projectID: UUID?
    var purpose: String?
    var visitCount: Int = 0
    var lastVisitedAt: Date = Date()

    init(latitude: Double, longitude: Double, address: String? = nil) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.visitCount = 1
        self.lastVisitedAt = Date()
    }
}
