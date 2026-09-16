import Foundation

/// A classification chosen on the home screen, waiting for the app to apply it.
///
/// The widget records the *decision*, never the consequence. Qualifying a trip applies the
/// country's mileage rule and then re-prices the rest of the tax year — a tiered scale makes
/// one trip's type ripple through every later trip — and that belongs in one process, with
/// the rule engine and the store, not in a widget extension racing the app over the same
/// figures.
///
/// Nothing is falsified if this is lost: the trip stays in the queue and is asked about
/// again. The failure mode is a question repeated, never an amount invented.
struct PendingQualification: Codable, Equatable, Sendable {
    let tripID: UUID
    let isBusiness: Bool
    let decidedAt: Date

    var tripType: TripType { isBusiness ? .business : .personal }
}

/// A stop asked for from the home screen.
///
/// `tripStartedAt` is what the widget could see when the button was drawn. The app honours
/// the request only if that is still the trip running — otherwise the drive it names has
/// already ended, and a stale request would stop whatever happened to be recording instead.
struct PendingStop: Codable, Equatable, Sendable {
    let tripStartedAt: Date?
    let requestedAt: Date
}

/// The one-way channel from the home screen to the app: the widget extension writes, the app
/// reads and clears.
///
/// Two plain files in the shared container. No database is involved on either side — the
/// extension must not touch the app's store, and a couple of JSON files cannot be left
/// half-written (`.atomic`) or read twice (`drain` removes as it reads).
struct SharedInbox: Sendable {
    /// `nil` when the App Group is not reachable — an entitlement that has not been granted,
    /// or a unit test host without one. Every operation is then a no-op rather than a crash.
    let directory: URL?

    static let shared = SharedInbox(directory: WidgetSnapshotStore.containerURL)

    private var qualificationsURL: URL? { directory?.appendingPathComponent("pending-qualifications.json") }
    private var stopURL: URL? { directory?.appendingPathComponent("pending-stop.json") }

    // MARK: - Qualifications

    func record(_ decision: PendingQualification) {
        guard let qualificationsURL else { return }
        // One answer per trip: tapping Business then Personal on the same trip leaves the
        // last answer, not both.
        var all = qualifications().filter { $0.tripID != decision.tripID }
        all.append(decision)
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: qualificationsURL, options: .atomic)
    }

    func qualifications() -> [PendingQualification] {
        guard let qualificationsURL, let data = try? Data(contentsOf: qualificationsURL) else { return [] }
        return (try? JSONDecoder().decode([PendingQualification].self, from: data)) ?? []
    }

    /// Reads and clears in one step, so a decision cannot be applied twice.
    @discardableResult
    func drainQualifications() -> [PendingQualification] {
        let all = qualifications()
        if let qualificationsURL { try? FileManager.default.removeItem(at: qualificationsURL) }
        return all
    }

    // MARK: - Stop

    func requestStop(tripStartedAt: Date?, at date: Date = .now) {
        guard let stopURL else { return }
        let request = PendingStop(tripStartedAt: tripStartedAt, requestedAt: date)
        guard let data = try? JSONEncoder().encode(request) else { return }
        try? data.write(to: stopURL, options: .atomic)
    }

    @discardableResult
    func takeStopRequest() -> PendingStop? {
        guard let stopURL, let data = try? Data(contentsOf: stopURL) else { return nil }
        let request = try? JSONDecoder().decode(PendingStop.self, from: data)
        try? FileManager.default.removeItem(at: stopURL)
        return request
    }
}
