import ActivityKit
import Foundation

/// Drives the Live Activity for the trip in progress.
///
/// It no longer decides *when* to push. It used to, on a throttle of its own, while the
/// driving screen redrew on every fix — so the phone and the CarPlay dashboard showed the
/// same drive at two different distances. The schedule now lives in `DistanceBroadcast`,
/// above both, and this type pushes exactly what it is handed.
///
/// The 5 s floor that schedule enforces is also what keeps ActivityKit from rate-limiting
/// the app: past a certain rate it stops applying updates altogether, and a lock screen
/// frozen mid-drive looks exactly like tracking that has died.
///
/// Every `Activity` call happens on the main actor. `Activity` is not `Sendable`, so handing
/// one to a detached task is a data race Swift 6 refuses outright.
@MainActor
final class TripActivityController {
    /// Only the identifier is held. `Activity` is not `Sendable`, so the live object is
    /// looked up again *inside* the task that awaits it — a value that originates there is
    /// never sent across an isolation boundary, which is what Swift 6 objects to.
    private var activityID: String?

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
        guard !strayIDs.isEmpty else { return }
        Task {
            for activity in Activity<TripAttributes>.activities where strayIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func start(vehicleName: String, unit: DistanceUnit, startedAt: Date, locale: Locale = .current) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activityID == nil else { return }
        let attributes = TripAttributes(vehicleName: vehicleName)
        let state = TripAttributes.ContentState(
            distanceMeters: 0, startedAt: startedAt, unitRaw: unit.rawValue, localeIdentifier: locale.identifier
        )
        activityID = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        ).id
    }

    /// Pushes a figure that has already been through the schedule. No decision is taken here
    /// — a second opinion about when to publish is what produced two different distances.
    func update(distanceMeters: Double, startedAt: Date, unit: DistanceUnit, locale: Locale = .current) {
        guard let activityID else { return }
        let state = TripAttributes.ContentState(
            distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue,
            localeIdentifier: locale.identifier
        )
        Task {
            for activity in Activity<TripAttributes>.activities where activity.id == activityID {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    func end(distanceMeters: Double, startedAt: Date, unit: DistanceUnit, locale: Locale = .current) {
        guard let activityID else { return }
        let state = TripAttributes.ContentState(
            distanceMeters: distanceMeters, startedAt: startedAt, unitRaw: unit.rawValue,
            localeIdentifier: locale.identifier
        )
        Task {
            for activity in Activity<TripAttributes>.activities where activity.id == activityID {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        self.activityID = nil
    }
}
