import Foundation
import SwiftData
import XCTest
@testable import MileagePocket

/// A store written by the build that is already on people's phones, reopened by the build
/// being made now.
///
/// This is the one failure mode that silently costs a user everything they recorded: change a
/// `@Model` in a way SwiftData cannot migrate, and `PersistenceController.openStore` sets the
/// unreadable file aside and opens an empty one in its place. The app then launches, looks
/// perfectly healthy, and contains nothing. Nobody finds out until someone opens Trips —
/// possibly weeks of drives later, and possibly after the file has been set aside twice.
///
/// `v1.store` is not a fabricated fixture: it is a real store, produced by installing the
/// shipped build on a simulator, seeding it, and copying the file out. Regenerate it the same
/// way — never by hand — when a deliberate migration lands.
final class StoreUpgradeTests: XCTestCase {
    /// Read from the source tree rather than the test bundle: a `.store` is a binary
    /// resource, and the alternative was teaching the project generator to copy it.
    private var fixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/ShippedStore/v1.store")
    }

    func testAStoreFromTheShippedBuildStillOpensAndStillHasEverythingInIt() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path),
            "the fixture store is missing — this test cannot protect anything without it"
        )

        // Copied, because opening a store mutates it and the fixture has to stay the version
        // it claims to be.
        let directory = URL.temporaryDirectory.appending(path: "store-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: copy)

        let configuration = ModelConfiguration(
            schema: PersistenceController.schema,
            url: copy,
            cloudKitDatabase: .none
        )
        // A throw here *is* the defect: it is exactly what makes the app set the file aside
        // on a real phone.
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
        let context = ModelContext(container)
        let trips = try context.fetch(FetchDescriptor<Trip>())

        XCTAssertEqual(trips.count, 8, "the trips recorded by the shipped build did not survive the upgrade")
        // Not just a row count: the fields have to come back too, since a migration can keep
        // the rows and drop what is in them.
        XCTAssertTrue(trips.allSatisfy { $0.startedAt.timeIntervalSince1970 > 0 })
        XCTAssertTrue(trips.contains { $0.distanceMeters > 0 })
    }

    /// The migration that is about to happen on every phone that already has the app.
    ///
    /// iCloud went from off to on. On the next launch, a store full of local trips is opened
    /// with the CloudKit database attached for the first time — and if that fails,
    /// `openStore` sets the file aside and opens an empty one. The user would see a working
    /// app with nothing in it, having done nothing but install an update.
    func testTurningICloudOnDoesNotCostTheTripsAlreadyRecorded() throws {
        let directory = URL.temporaryDirectory.appending(path: "cloud-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: copy)

        let configuration = ModelConfiguration(
            schema: PersistenceController.schema,
            url: copy,
            cloudKitDatabase: .private(PersistenceController.cloudKitContainerIdentifier)
        )
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
        let trips = try ModelContext(container).fetch(FetchDescriptor<Trip>())

        XCTAssertEqual(trips.count, 8, "turning iCloud on emptied a store that had trips in it")
    }

    /// The container is named in two places. A typo in either is not a crash and not a build
    /// error — it is sync that never happens, on a switch the user has turned on.
    func testTheContainerIsNamedTheSameInBothPlaces() {
        XCTAssertEqual(
            PersistenceController.cloudKitContainerIdentifier,
            CloudKitAvailability.containerIdentifier
        )
        XCTAssertEqual(PersistenceController.cloudKitContainerIdentifier, "iCloud.company.lno.mileage")
    }

    /// The store's location is part of the contract with every phone that already has one.
    ///
    /// Moving it — into the App Group, for instance, which was proposed so the widget could
    /// read it — orphans every existing install unless the same commit carries a migration.
    /// This is a tripwire, not a prohibition: if the move is deliberate, this test is what
    /// forces it to be deliberate.
    func testTheStoreStaysWhereEveryExistingInstallAlreadyPutIt() {
        let url = PersistenceController.defaultStoreURL
        XCTAssertEqual(url.lastPathComponent, "default.store")
        XCTAssertTrue(url.path.contains("Application Support"), "unexpected location: \(url.path)")
        XCTAssertFalse(
            url.path.contains(WidgetSnapshotStore.appGroupIdentifier),
            "the store moved into the App Group — every existing install's trips are now orphaned"
        )
    }
}
