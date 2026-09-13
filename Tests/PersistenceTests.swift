import XCTest
import SwiftData
@testable import MileagePocket

final class PersistenceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        return ModelContext(container)
    }

    func testSchemaOpensWithEveryModel() throws {
        XCTAssertNoThrow(try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true))
    }

    func testTripRoundTrips() throws {
        let context = try makeContext()
        let trip = Trip()
        trip.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        trip.endedAt = Date(timeIntervalSince1970: 1_700_001_662)
        trip.rawDistanceMeters = 24_300
        trip.startAddress = "Paris"
        trip.endAddress = "Versailles"
        trip.tripType = .business
        trip.purpose = "Client meeting"
        trip.countryCode = "FR"
        trip.mileageRate = Decimal(string: "0.647")
        trip.calculatedAmount = Decimal(string: "15.73")
        trip.currencyCode = "EUR"
        context.insert(trip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(fetched.count, 1)
        let stored = try XCTUnwrap(fetched.first)
        XCTAssertEqual(stored.rawDistanceMeters, 24_300)
        XCTAssertEqual(stored.endAddress, "Versailles")
        XCTAssertEqual(stored.tripType, .business)
        XCTAssertEqual(stored.calculatedAmount, Decimal(string: "15.73"))
        XCTAssertEqual(stored.duration, 1662)
    }

    /// CloudKit refuses a schema whose properties have no default; a model that cannot be
    /// created bare is that defect showing up early.
    func testEveryModelCanBeCreatedWithoutArguments() throws {
        let context = try makeContext()
        context.insert(Trip())
        context.insert(Vehicle())
        context.insert(Client())
        context.insert(Project())
        context.insert(UserSettings())
        context.insert(LocationPoint(tripID: UUID(), latitude: 0, longitude: 0, timestamp: .now, horizontalAccuracy: 5))
        context.insert(FrequentLocation(latitude: 0, longitude: 0))
        context.insert(ActiveTripState(tripID: UUID()))
        XCTAssertNoThrow(try context.save())
    }

    func testCorrectedDistanceWinsOverRawDistance() {
        let trip = Trip()
        trip.rawDistanceMeters = 24_300
        XCTAssertEqual(trip.distanceMeters, 24_300)
        trip.correctedDistanceMeters = 25_000
        XCTAssertEqual(trip.distanceMeters, 25_000)
        XCTAssertEqual(trip.rawDistanceMeters, 24_300, "a manual correction must not overwrite the measured distance")
    }

    func testDistanceUnitConversion() {
        XCTAssertEqual(DistanceUnit.kilometers.value(fromMeters: 24_300), 24.3, accuracy: 0.0001)
        XCTAssertEqual(DistanceUnit.miles.value(fromMeters: 1609.344), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DistanceUnit.miles.meters(fromValue: 10), 16_093.44, accuracy: 0.001)
    }
}

/// The store failing to open is the one launch-time fault a user cannot diagnose: the app
/// simply looks brand new. What it must never do is delete the old file, and what it must
/// never do quietly is fall back to memory — a week of drives recorded into an in-memory
/// store vanishes at the next launch with nothing said.
final class StoreRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "store-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnUnreadableStoreIsMovedAsideAndNeverDeleted() throws {
        let store = directory.appending(path: "default.store")
        try Data("not a database".utf8).write(to: store)
        try Data("wal".utf8).write(to: URL(filePath: store.path + "-wal"))

        let moved = try PersistenceController.setStoreAside(storeURL: store)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.path),
            "the path has to be clear, or the next open finds the same broken file"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: moved.path),
            "a store that cannot be read today can be read by a later build — never delete it"
        )
        XCTAssertEqual(try Data(contentsOf: moved), Data("not a database".utf8))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: moved.path + "-wal"),
            "the journal moves with it, or SQLite replays it into the fresh store"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path + "-wal"))
    }

    func testMovingAsideAStoreThatIsNotThereFails() {
        // Reported rather than swallowed: if there is nothing to move, the reason the open
        // failed is not a broken file and pretending otherwise hides it.
        XCTAssertThrowsError(
            try PersistenceController.setStoreAside(storeURL: directory.appending(path: "missing.store"))
        )
    }
}
