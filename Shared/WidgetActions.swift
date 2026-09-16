import AppIntents
import Foundation
import WidgetKit

/// How an intent performed inside the *app's* process reaches the running app.
///
/// An intent is a value the system creates; it has no way of knowing about the object graph
/// the app built at launch. The app plants a closure here at bootstrap, and an intent that
/// runs in-app calls it. In the widget extension nothing sets it, and it stays nil — which
/// is correct: over there the app's recorder and store do not exist.
enum WidgetActionBridge {
    @MainActor static var applyPendingActions: (() -> Void)?
}

/// Answers "business or personal?" for one named trip, from the home screen.
///
/// This runs in the widget extension, which has no store and no rule engine — so it records
/// the answer and nothing else. The consequence, which is a tax figure and a re-pricing of
/// the whole year, is applied by the app; see `PendingQualification`. The widget's own face
/// is updated here so the tap is visibly taken rather than appearing to do nothing.
struct QualifyTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Classify trip"
    /// Not offered in Shortcuts: it takes a trip identifier only the widget can supply, so
    /// as a standalone action it would be an action nobody can run.
    static let isDiscoverable = false

    @Parameter(title: "Trip") var tripID: String
    @Parameter(title: "Business") var isBusiness: Bool

    init() {}

    init(tripID: UUID, isBusiness: Bool) {
        self.tripID = tripID.uuidString
        self.isBusiness = isBusiness
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: tripID) else { return .result() }
        SharedInbox.shared.record(PendingQualification(tripID: id, isBusiness: isBusiness, decidedAt: .now))
        if let snapshot = WidgetSnapshotStore.read() {
            WidgetSnapshotStore.write(snapshot.answering(id))
        }
        await MainActor.run { WidgetActionBridge.applyPendingActions?() }
        return .result()
    }
}

/// Ends the drive in progress, from the home screen.
///
/// Unlike the buttons above, this one opens the app — deliberately, and it is the only
/// honest way to do it: ending a trip means closing the route, stopping the location
/// manager and writing the trip, none of which exist in the widget extension's process.
/// `openAppWhenRun` puts `perform()` in the app's process, where all three do.
struct StopTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop trip"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    /// When the trip the button was drawn for began. The app refuses a request that no
    /// longer matches the drive in progress, so a tap that arrives late cannot stop a
    /// different trip than the one the user was looking at.
    @Parameter(title: "Started at") var tripStartedAt: Date?

    init() {}

    init(tripStartedAt: Date?) {
        self.tripStartedAt = tripStartedAt
    }

    func perform() async throws -> some IntentResult {
        SharedInbox.shared.requestStop(tripStartedAt: tripStartedAt)
        // Two orderings are possible and both are covered: if the app was not running, this
        // does nothing and the request is applied when it finishes launching; if it was, the
        // trip stops now rather than waiting for a foreground transition that already
        // happened.
        await MainActor.run { WidgetActionBridge.applyPendingActions?() }
        return .result()
    }
}
