import CoreLocation
import Foundation
import SwiftData
@testable import MileagePocket

/// A recorder that does nothing, for tests that need an `AppDependencies` but no GPS.
///
/// Shared rather than redeclared per test class: three copies had already drifted apart, and
/// a protocol change then had to be applied three times before the suite would compile.
@MainActor
final class InertRecorder: TripRecording {
    var state: RecorderState = .idle
    var onUpdate: (() -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var currentDistanceMeters: Double = 0
    var startedAt: Date?
    var routeSamples: [LocationSample] = []

    func start(vehicleID: UUID?) throws {}
    func resume(_ trip: Trip) throws {}
    func stop() throws -> Trip { throw RecorderError.notRecording }
    func resumeIfNeeded() throws -> ResumeOutcome { .none }
    func attachPlaces(to trip: Trip) async {}
    func requestPermission() {}
}
