import ActivityKit
import Foundation

/// Drives the Live Activity for the trip in progress.
///
/// Updates are throttled: ActivityKit rate-limits an app that pushes too often, and past a
/// point the system simply stops applying them — so the lock screen would freeze mid-drive,
/// which looks exactly like the tracking having died.
@MainActor
final class TripActivityController {
    private var activity: Activity<TripAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastDistance: Double = 0

    private let minimumInterval: TimeInterval = 30
    private let minimumDistanceDelta: Double = 500

    var isRunning: Bool { activity != nil }

    func start(vehicleName: String, unit: DistanceUnit, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = TripAttributes(vehicleName: vehicleName)
        let state = TripAttributes.ContentState(distanceMeters: 0, startedAt: startedAt, unitRaw: unit.rawValue)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastUpdate = .now
        lastDistance = 0
    }

    func update(distanceMeters: Double, startedAt: Date, unit: DistanceUnit) {
        guard let activity else { return }
        let elapsed = Date.now.timeIntervalSince(lastUpdate)
        let moved = abs(distanceMeters - lastDistance)
        guard elapsed >= minimumInterval || moved >= minimumDistanceDelta else { return }

        lastUpdate = .now
        lastDistance = distanceMeters
        let state = TripAttributes.ContentState(distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(distanceMeters: Double, startedAt: Date, unit: DistanceUnit) {
        guard let activity else { return }
        let state = TripAttributes.ContentState(distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
