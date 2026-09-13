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

    // The lock screen and CarPlay showed 0.0 km while the app itself had 0.2: at 30 s / 500 m
    // the first push of a trip lands long after the driver has already looked. The Info.plist
    // declares NSSupportsLiveActivitiesFrequentUpdates, which is what buys this budget.
    private let minimumInterval: TimeInterval = 5
    private let minimumDistanceDelta: Double = 100

    var isRunning: Bool { activityID != nil }

    /// Reconciles the lock screen with what the app is actually doing, at launch.
    ///
    /// An activity outlives the process that started it: force-quit mid-drive and the lock
    /// screen goes on showing a trip with a frozen distance, forever, because nothing owns
    /// it any more. Worse, the next START passed the `activityID == nil` guard and requested
    /// a *second* activity beside the stranded one.
    /// - Parameter isRecording: whether the recorder picked the trip back up.
    func adopt(isRecording: Bool) {
        let existing = Activity<TripAttributes>.activities
        guard let first = existing.first else { return }

        // Kept as ids, never as `Activity` values: `Activity` is not `Sendable`, so handing
        // one to a task is a data race Swift 6 refuses. The live object is looked up again
        // inside the task, where it originates and never crosses a boundary.
        let keptID = isRecording ? first.id : nil
        let strayIDs = existing.map(\.id).filter { $0 != keptID }

        activityID = keptID
        if keptID != nil {
            // The throttle must not hold back the first push of the resumed trip.
            lastUpdate = .distantPast
            lastDistance = 0
        }
        guard !strayIDs.isEmpty else { return }
        Task {
            for activity in Activity<TripAttributes>.activities where strayIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func start(vehicleName: String, unit: DistanceUnit, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activityID == nil else { return }
        let attributes = TripAttributes(vehicleName: vehicleName)
        let state = TripAttributes.ContentState(distanceMeters: 0, startedAt: startedAt, unitRaw: unit.rawValue)
        activityID = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        ).id
        // Distant past, not now: otherwise the very first distance update is held back by the
        // throttle and the lock screen sits at 0.0 km for the opening seconds of every trip.
        lastUpdate = .distantPast
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
