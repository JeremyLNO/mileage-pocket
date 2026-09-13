import CoreLocation
import Foundation
import SwiftData

enum RecorderState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date, distanceMeters: Double, duration: TimeInterval)
    /// The vehicle has been standing still long enough that the trip is on hold. The
    /// distance so far is not carried in this case — read `TripRecorder.distanceMeters`,
    /// which is live in every state.
    case paused

    /// Distance carried by a recording state, 0 otherwise.
    var distanceMeters: Double {
        if case .recording(_, let meters, _) = self { return meters }
        return 0
    }

    var isActive: Bool { self != .idle }
}

@MainActor
protocol TripRecording: AnyObject {
    var state: RecorderState { get }
    /// Called on the main actor after every accepted fix. The recorder is deliberately not
    /// `@Observable` — it is a service, not view state — so this is how the UI learns that
    /// the distance moved.
    var onUpdate: (() -> Void)? { get set }
    /// Forwarded from the provider so the app can react to a prompt answered mid-trip.
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    /// When the trip began. Read this for the on-screen stopwatch rather than digging it out
    /// of `state`: the `.paused` case carries no payload, and a stopwatch that resets at
    /// every red light is worse than no stopwatch.
    var startedAt: Date? { get }
    /// Distance accumulated so far, valid in **every** state. `RecorderState.distanceMeters`
    /// reports 0 while paused because the enum has nowhere to put it; the distance itself
    /// does not evaporate when the car stops.
    var currentDistanceMeters: Double { get }
    /// Accepted fixes so far, for drawing the live route.
    var routeSamples: [LocationSample] { get }
    func start(vehicleID: UUID?) throws
    func stop() async throws -> Trip
    func resumeIfNeeded() throws
    /// Asks for the location permission. The screen that asks does not need to know a
    /// `LocationProviding` exists.
    func requestPermission()
}

enum RecorderError: Error, Equatable {
    case alreadyRecording
    case notRecording
    /// Location is off or refused. Recording anyway produced the worst outcome there is: a
    /// running timer, a driving screen, and a trip saved at 0 m with nothing said.
    case locationUnavailable(CLAuthorizationStatus)
}

/// Records one drive: fixes in, a `Trip` out.
///
/// Two things are load-bearing here and both are about losing data rather than losing
/// precision. First, `ActiveTripState` is rewritten on **every** accepted fix, so a crash,
/// a force-quit or an out-of-memory kill costs at most one fix instead of the whole drive.
/// Second, `stop()` saves the trip *before* it reverse-geocodes: geocoding is a network call
/// that can hang for seconds, and a trip that exists without its addresses is recoverable
/// while a trip that was never written is not.
@MainActor
final class TripRecorder: TripRecording {
    private(set) var state: RecorderState = .idle
    /// Live distance, valid in every state — including `.paused`, which the enum cannot carry.
    private(set) var currentDistanceMeters: Double = 0
    var onUpdate: (() -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    /// Accepted fixes so far, for the live map. Rebuilt from the store after a resume.
    private(set) var routeSamples: [LocationSample] = []
    private(set) var startedAt: Date?

    /// How hard the stored route is thinned. 10 m is invisible at any zoom a phone map
    /// offers and cuts a one-hour drive to a few hundred points.
    private static let routeToleranceMeters: Double = 10

    private let context: ModelContext
    private let provider: LocationProviding
    private let geocoder: Geocoding
    private let config: FilterConfig
    private let now: () -> Date

    private var filter: LocationFilter
    private var activeState: ActiveTripState?
    private var tripID: UUID?
    private var vehicleID: UUID?
    private var startCoordinate: (latitude: Double, longitude: Double)?
    private var lastCoordinate: (latitude: Double, longitude: Double)?

    init(
        context: ModelContext,
        provider: LocationProviding,
        geocoder: Geocoding,
        config: FilterConfig = FilterConfig(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.context = context
        self.provider = provider
        self.geocoder = geocoder
        self.config = config
        self.now = now
        self.filter = LocationFilter(config: config)
        provider.onAuthorizationChange = { [weak self] status in
            self?.onAuthorizationChange?(status)
        }
    }

    // MARK: - Lifecycle

    func start(vehicleID: UUID?) throws {
        guard state == .idle else { throw RecorderError.alreadyRecording }
        // Refused up front rather than recording nothing in silence. `.notDetermined` is
        // allowed through: the prompt is raised alongside, and the authorisation callback
        // starts delivery as soon as it is answered.
        switch provider.authorization {
        case .denied, .restricted:
            throw RecorderError.locationUnavailable(provider.authorization)
        default:
            break
        }

        // A leftover row from an abandoned trip would be offered as "resume" on the next
        // launch, attaching this drive's fixes to the wrong trip.
        try discardActiveState()

        let id = UUID()
        let startTime = now()
        let active = ActiveTripState(tripID: id, startedAt: startTime, vehicleID: vehicleID)
        context.insert(active)
        try context.save()

        tripID = id
        startedAt = startTime
        self.vehicleID = vehicleID
        activeState = active
        filter = LocationFilter(config: config)
        currentDistanceMeters = 0
        routeSamples = []
        startCoordinate = nil
        lastCoordinate = nil
        state = .recording(startedAt: startTime, distanceMeters: 0, duration: 0)

        listen()
    }

    var authorizationStatus: CLAuthorizationStatus { provider.authorization }

    func requestPermission() {
        provider.requestAlways()
    }

    func resumeIfNeeded() throws {
        guard state == .idle else { return }
        guard let active = try fetchActiveState() else { return }

        tripID = active.tripID
        startedAt = active.startedAt
        vehicleID = active.vehicleID
        activeState = active
        currentDistanceMeters = active.distanceMeters
        // Seed the filter with the distance already banked: it restarts with no previous
        // fix, so the first one after a resume simply re-anchors and counts nothing.
        filter = LocationFilter(config: config, startingDistanceMeters: active.distanceMeters)
        if let latitude = active.startLatitude, let longitude = active.startLongitude {
            startCoordinate = (latitude, longitude)
        }
        if let latitude = active.lastLatitude, let longitude = active.lastLongitude {
            lastCoordinate = (latitude, longitude)
        }
        routeSamples = (try? storedPoints(for: active.tripID))?.map(Self.sample(from:)) ?? []
        state = .recording(
            startedAt: active.startedAt,
            distanceMeters: active.distanceMeters,
            duration: now().timeIntervalSince(active.startedAt)
        )

        listen()
    }

    func stop() async throws -> Trip {
        guard let tripID, let startedAt else { throw RecorderError.notRecording }

        // Cut the feed before the awaits below, or a fix that arrives mid-geocode is filed
        // against a trip that has already ended.
        provider.stopUpdates()
        provider.onSample = nil

        let endedAt = now()
        let points = (try? storedPoints(for: tripID)) ?? []
        let samples = points.map(Self.sample(from:))

        let trip = Trip(id: tripID, startedAt: startedAt)
        trip.endedAt = endedAt
        trip.rawDistanceMeters = filter.totalDistanceMeters
        trip.vehicleID = vehicleID
        trip.startLatitude = startCoordinate?.latitude ?? samples.first?.latitude
        trip.startLongitude = startCoordinate?.longitude ?? samples.first?.longitude
        trip.endLatitude = lastCoordinate?.latitude ?? samples.last?.latitude
        trip.endLongitude = lastCoordinate?.longitude ?? samples.last?.longitude
        if samples.count > 1 {
            trip.encodedRoute = RouteCompactor.encode(
                RouteCompactor.simplify(samples, toleranceMeters: Self.routeToleranceMeters)
            )
        }
        trip.updatedAt = endedAt
        context.insert(trip)

        // The fixes were only ever a crash-recovery buffer; the polyline replaces them.
        // Leaving them would push hundreds of thousands of rows into the user's iCloud.
        for point in points { context.delete(point) }
        if let activeState { context.delete(activeState) }
        try context.save()

        reset()

        // Exactly two lookups per trip — where it started and where it ended. One per fix
        // would be thousands of calls and a rate-limited app by the second drive.
        if let latitude = trip.startLatitude, let longitude = trip.startLongitude {
            let place = await geocoder.place(latitude: latitude, longitude: longitude)
            trip.startAddress = place?.town
            trip.startStreet = place?.street
        }
        if let latitude = trip.endLatitude, let longitude = trip.endLongitude {
            let place = await geocoder.place(latitude: latitude, longitude: longitude)
            trip.endAddress = place?.town
            trip.endStreet = place?.street
        }
        trip.updatedAt = now()
        try? context.save()

        return trip
    }

    // MARK: - Ingestion

    private func listen() {
        provider.onSample = { [weak self] sample in
            self?.ingest(sample)
        }
        provider.startUpdates()
    }

    private func ingest(_ sample: LocationSample) {
        guard let tripID, let startedAt, let activeState else { return }

        switch filter.accept(sample, now: now()) {
        case .accepted, .bridged:
            currentDistanceMeters = filter.totalDistanceMeters
            routeSamples.append(sample)
            if startCoordinate == nil {
                startCoordinate = (sample.latitude, sample.longitude)
                activeState.startLatitude = sample.latitude
                activeState.startLongitude = sample.longitude
            }
            lastCoordinate = (sample.latitude, sample.longitude)

            context.insert(LocationPoint(
                tripID: tripID,
                latitude: sample.latitude,
                longitude: sample.longitude,
                timestamp: sample.timestamp,
                horizontalAccuracy: sample.horizontalAccuracy,
                altitude: sample.altitude,
                speed: sample.speed,
                cumulativeDistanceMeters: currentDistanceMeters
            ))

            activeState.distanceMeters = currentDistanceMeters
            activeState.lastLatitude = sample.latitude
            activeState.lastLongitude = sample.longitude
            activeState.lastUpdatedAt = sample.timestamp
            // Saved per accepted fix, not per batch: the whole point of this row is to
            // survive a kill that arrives at the worst possible moment.
            try? context.save()

            state = .recording(
                startedAt: startedAt,
                distanceMeters: currentDistanceMeters,
                duration: now().timeIntervalSince(startedAt)
            )

        case .paused:
            state = .paused

        case .rejected:
            // A rejected fix still means time passed; the UI's clock is driven by its own
            // timer, so there is nothing to publish here.
            return
        }

        onUpdate?()
    }

    // MARK: - Store

    private func storedPoints(for tripID: UUID) throws -> [LocationPoint] {
        let descriptor = FetchDescriptor<LocationPoint>(
            predicate: #Predicate { $0.tripID == tripID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchActiveState() throws -> ActiveTripState? {
        try context.fetch(
            FetchDescriptor<ActiveTripState>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        ).first
    }

    private func discardActiveState() throws {
        for state in try context.fetch(FetchDescriptor<ActiveTripState>()) {
            for point in try storedPoints(for: state.tripID) { context.delete(point) }
            context.delete(state)
        }
        try context.save()
    }

    private static func sample(from point: LocationPoint) -> LocationSample {
        LocationSample(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracy: point.horizontalAccuracy,
            altitude: point.altitude,
            speed: point.speed,
            timestamp: point.timestamp
        )
    }

    private func reset() {
        state = .idle
        currentDistanceMeters = 0
        routeSamples = []
        filter = LocationFilter(config: config)
        activeState = nil
        tripID = nil
        startedAt = nil
        vehicleID = nil
        startCoordinate = nil
        lastCoordinate = nil
    }
}
