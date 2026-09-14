import CoreMotion
import Foundation
import UIKit

/// What the phone's motion coprocessor says about how its owner is moving.
///
/// CarPlay answers "is this phone in *that* car". This answers "is this person driving" —
/// in a hire car, in someone else's, in their own on a day the head unit is off. It is the
/// same classifier the Health app uses for activity, it runs on the coprocessor rather than
/// on the CPU, and the app only ever reads it.
///
/// The rule it feeds is deliberately conservative. A trip that starts by itself and should
/// not have is a line on a tax document that never happened; a trip that fails to start is
/// a line the driver adds by hand. The second is a nuisance, the first is a false statement.
enum DriveSignal {
    enum State: Equatable {
        case driving
        case notDriving
        /// The classifier is not sure. Nothing is ever decided on this: acting on a guess is
        /// how an app invents journeys.
        case unknown
    }

    /// `CMMotionActivityConfidence.medium`. Low confidence is the coprocessor saying it has
    /// not made up its mind, and it says it often — at a bus stop, on a train, in a lift.
    static let minimumConfidence = CMMotionActivityConfidence.medium.rawValue

    static func state(
        automotive: Bool,
        stationary: Bool,
        walking: Bool,
        cycling: Bool,
        confidence: Int
    ) -> State {
        guard confidence >= minimumConfidence else { return .unknown }
        // Automotive *and* stationary is a real, frequent combination: a car at a red light.
        // It is still a drive, and the trip's own pause detection handles the standing part.
        if automotive { return .driving }
        if walking || cycling || stationary { return .notDriving }
        return .unknown
    }
}

@MainActor
protocol DriveDetecting: AnyObject {
    var isAvailable: Bool { get }
    var onChange: ((DriveSignal.State) -> Void)? { get set }
    func start()
    func stop()
    /// Asks the motion history what is happening right now.
    ///
    /// Live updates only arrive on a *change*, so an app that wakes up mid-drive — which is
    /// exactly what the background watch arranges — would otherwise hear nothing at all
    /// until the driver stopped.
    func checkNow()
}

@MainActor
final class DriveDetector: DriveDetecting {
    /// How far back a wake-up looks. Long enough to catch a drive already under way, short
    /// enough that yesterday's commute cannot start today's trip.
    static let lookback: TimeInterval = 15 * 60

    var onChange: ((DriveSignal.State) -> Void)?

    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue.main
    private var isRunning = false
    private var observer: NSObjectProtocol?
    private var lastState: DriveSignal.State = .unknown

    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func start() {
        guard isAvailable, !isRunning else { return }
        isRunning = true
        manager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self, let activity else { return }
            MainActor.assumeIsolated { self.publish(Self.state(of: activity)) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        checkNow()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopActivityUpdates()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lastState = .unknown
    }

    func checkNow() {
        guard isAvailable else { return }
        let now = Date()
        manager.queryActivityStarting(from: now.addingTimeInterval(-Self.lookback), to: now, to: queue) {
            [weak self] activities, _ in
            guard let self, let latest = activities?.last else { return }
            MainActor.assumeIsolated { self.publish(Self.state(of: latest)) }
        }
    }

    private func publish(_ state: DriveSignal.State) {
        // `.unknown` is not a change of mind, it is the absence of one: reporting it would
        // end a trip every time the classifier hesitated.
        guard state != .unknown, state != lastState else { return }
        lastState = state
        onChange?(state)
    }

    private static func state(of activity: CMMotionActivity) -> DriveSignal.State {
        DriveSignal.state(
            automotive: activity.automotive,
            stationary: activity.stationary,
            walking: activity.walking,
            cycling: activity.cycling,
            confidence: activity.confidence.rawValue
        )
    }
}
