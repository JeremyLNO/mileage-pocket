import Foundation

/// The little the home screen widget needs: this month's figures and whether a trip is
/// running. Written by the app into the shared App Group container whenever a trip ends,
/// read by the widget — which has no access to the app's SwiftData store.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var monthLabel: String
    var distanceMeters: Double
    var unitRaw: String
    var formattedAmount: String?
    var isTripInProgress: Bool
    var updatedAt: Date

    var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .kilometers }

    static let placeholder = WidgetSnapshot(
        monthLabel: "September",
        distanceMeters: 486_000,
        unitRaw: DistanceUnit.kilometers.rawValue,
        formattedAmount: nil,
        isTripInProgress: false,
        updatedAt: .now
    )
}

enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.company.lno.mileage"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // A failed write leaves the previous snapshot in place, which is a stale widget —
        // strictly better than an empty one.
        try? data.write(to: fileURL, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
