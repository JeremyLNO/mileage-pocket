import ActivityKit
import Foundation

/// Drives the Live Activity for the trip in progress.
///
/// Updates are throttled: ActivityKit rate-limits an app that pushes too often, and past a
/// point it simply stops applying them — so the lock screen would freeze mid-drive, which
/// looks exactly like the tracking having died.
///
/// Every `Activity` call happens on the main actor. `Activity` is not `Sendable`, so handing
/// one to a detached task is a data race Swift 6 refuses outright.
@MainActor
final class TripActivityController {
    /// Only the identifier is held. `Activity` is not `Sendable`, so the live object is
    /// looked up again *inside* the task that awaits it — a value that originates there is
    /// never sent across an isolation boundary, which is what Swift 6 objects to.
    private var activityID: String?
    private var lastUpdate = Date.distantPast
    private var lastDistance: Double = 0

    private let minimumInterval: TimeInterval = 30
    private let minimumDistanceDelta: Double = 500

    var isRunning: Bool { activityID != nil }

    func start(vehicleName: String, unit: DistanceUnit, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activityID == nil else { return }
        let attributes = TripAttributes(vehicleName: vehicleName)
        let state = TripAttributes.ContentState(distanceMeters: 0, startedAt: startedAt, unitRaw: unit.rawValue)
        activityID = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        ).id
        lastUpdate = .now
        lastDistance = 0
    }

    func update(distanceMeters: Double, startedAt: Date, unit: DistanceUnit) {
        guard let activityID else { return }
        let elapsed = Date.now.timeIntervalSince(lastUpdate)
        let moved = abs(distanceMeters - lastDistance)
        guard elapsed >= minimumInterval || moved >= minimumDistanceDelta else { return }

        lastUpdate = .now
        lastDistance = distanceMeters
        let state = TripAttributes.ContentState(distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue)
        Task {
            for activity in Activity<TripAttributes>.activities where activity.id == activityID {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    func end(distanceMeters: Double, startedAt: Date, unit: DistanceUnit) {
        guard let activityID else { return }
        let state = TripAttributes.ContentState(distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue)
        Task {
            for activity in Activity<TripAttributes>.activities where activity.id == activityID {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        self.activityID = nil
    }
}
