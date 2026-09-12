import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// CloudKit is opt-out: when the user turns iCloud sync off we open the very same store
/// without the CloudKit database, so no data moves and nothing is lost either way.
enum PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.company.lno.mileage"

    static let schema = Schema([
        Trip.self,
        LocationPoint.self,
        Vehicle.self,
        Client.self,
        Project.self,
        FrequentLocation.self,
        UserSettings.self,
        ActiveTripState.self,
    ])

    static func makeContainer(cloudKitEnabled: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: (cloudKitEnabled && !inMemory) ? .private(cloudKitContainerIdentifier) : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Falls back to a local-only store, then to an in-memory store, rather than crashing on
    /// launch: an unavailable iCloud account or a schema CloudKit refuses must never leave
    /// the user staring at a dead app with their trips inside it.
    static func makeContainerWithFallback(cloudKitEnabled: Bool) -> ModelContainer {
        if cloudKitEnabled, let container = try? makeContainer(cloudKitEnabled: true) {
            return container
        }
        if let container = try? makeContainer(cloudKitEnabled: false) {
            return container
        }
        // An in-memory container cannot fail for a valid schema; a throw here is a
        // programming error in the model definitions, which tests catch.
        return try! makeContainer(cloudKitEnabled: false, inMemory: true)
    }
}
