import Foundation
import SwiftData

/// How the store actually opened. Anything other than `.healthy` is something the user has
/// to be told about, because both other cases mean their trips are not where they expect.
enum StoreHealth: Equatable, Sendable {
    /// The store on disk opened normally.
    case healthy
    /// The store on disk refused to open — a migration SwiftData could not perform, a
    /// truncated file — so it was **set aside** and a fresh one opened in its place. The old
    /// file is moved, never deleted: a store that cannot be read today can be read by a
    /// later build, and deleting it is the one step that cannot be undone.
    case recovered(setAside: URL)
    /// Nothing could be opened on disk at all. The app runs, but nothing recorded will
    /// survive the next launch — the one state where saying nothing would be indefensible.
    case ephemeral
}

struct StoreOpening {
    let container: ModelContainer
    let health: StoreHealth
}

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

    /// Where SwiftData puts the default store, plus the two sidecar files SQLite keeps
    /// beside it. Setting the store aside without its `-wal` leaves a fresh store that
    /// SQLite may still try to replay a journal into.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static func makeContainer(cloudKitEnabled: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: (cloudKitEnabled && !inMemory) ? .private(cloudKitContainerIdentifier) : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opens the store, degrading one step at a time rather than crashing on launch — and
    /// reporting which step it stopped on.
    ///
    /// The order matters. An unavailable iCloud account must cost the user sync, not their
    /// trips, so the local store is tried next. Only a store that will not open at all is
    /// set aside, and only then does an in-memory store come into it — announced, because a
    /// silent in-memory store is the worst outcome of the three: the app looks empty, the
    /// user records a week of drives into it, and every one of them disappears at the next
    /// launch. It used to do exactly that.
    /// - Parameter cloudKitEnabled: the user's preference. It is honoured only when the
    ///   build is genuinely entitled to the container — see `CloudKitAvailability`, and note
    ///   that getting this wrong is a launch crash, not a degraded feature.
    static func openStore(cloudKitEnabled: Bool) -> StoreOpening {
        if cloudKitEnabled, CloudKitAvailability.isEntitled, let container = try? makeContainer(cloudKitEnabled: true) {
            return StoreOpening(container: container, health: .healthy)
        }
        if let container = try? makeContainer(cloudKitEnabled: false) {
            return StoreOpening(container: container, health: .healthy)
        }
        if let setAside = try? setStoreAside(),
           let container = try? makeContainer(cloudKitEnabled: false) {
            return StoreOpening(container: container, health: .recovered(setAside: setAside))
        }
        // An in-memory container cannot fail for a valid schema; a throw here is a
        // programming error in the model definitions, which tests catch.
        return StoreOpening(container: try! makeContainer(cloudKitEnabled: false, inMemory: true), health: .ephemeral)
    }

    /// Renames the unreadable store — and its `-wal`/`-shm` siblings — out of the way.
    /// - Returns: where the main file went, so it can be named to the user.
    @discardableResult
    static func setStoreAside(
        storeURL: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        let url = storeURL ?? defaultStoreURL
        guard fileManager.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }

        let stamp = Self.setAsideStamp(for: now)
        let destination = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent)-unreadable-\(stamp)")

        try fileManager.moveItem(at: url, to: destination)
        // Best-effort for the sidecars: a missing one is normal, and it is the main file
        // whose move decides whether the next open sees a clean slate.
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(filePath: url.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            try? fileManager.moveItem(at: sidecar, to: URL(filePath: destination.path + suffix))
        }
        return destination
    }
}

private extension PersistenceController {
    /// Colons are legal in a file name on APFS but make the path miserable to type in a
    /// support exchange, which is the only reason this file is ever named out loud — so the
    /// separators are dropped. Built per call: `ISO8601DateFormatter` is a reference type
    /// with mutable state, and a shared instance is not concurrency-safe.
    static func setAsideStamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return formatter.string(from: date)
    }
}
