import Foundation

/// Thresholds the filter judges fixes against. Defaults come from spec §4.
struct FilterConfig: Sendable, Equatable {
    /// Metres of reported horizontal accuracy beyond which a fix is unusable.
    var maxAccuracy: Double = 50
    /// Metres per second above which movement between two fixes is a receiver artefact,
    /// not a car. 60 m/s = 216 km/h.
    var maxSpeed: Double = 60
    /// How old the *first* fix of a trip may be. CoreLocation replays a cached position on
    /// the opening callback; counting it anchors the trip wherever the phone last had a
    /// signal. It is deliberately not applied to later fixes — see `accept(_:now:)`.
    var maxStaleness: TimeInterval = 30
    /// Longest silence that may still be crossed in a straight line (a tunnel, a car park).
    var tunnelBridgeMaxGap: TimeInterval = 300
    /// Below this speed the vehicle counts as standing still.
    var stopSpeed: Double = 1
    /// How long it has to stand still before the trip is considered paused.
    var stopDuration: TimeInterval = 120

    init() {}
}

enum FilterRejection: Equatable, Sendable {
    case poorAccuracy
    case stale
    case outOfOrder
    case implausibleSpeed
    case belowNoiseFloor
    case gapTooLong
}

enum FilterDecision: Equatable, Sendable {
    /// Counted normally.
    case accepted(distanceMeters: Double)
    /// Counted across a GPS silence short enough, and consistent enough, to trust.
    case bridged(distanceMeters: Double)
    case rejected(FilterRejection)
    /// The vehicle has been standing still long enough that the trip is on hold.
    case paused
}

/// Turns a stream of GPS fixes into a distance a user can put on an expense claim.
///
/// It is a value type on purpose: no clock of its own, no CoreLocation, no I/O. Feed it an
/// array and you get the same answer every time, on any machine — which is the only way the
/// numbers below can be defended.
///
/// ## Why there is a smoother in here
///
/// Rules 1→6 of the spec reject *bad* fixes, but they do nothing about ordinary noise, and
/// ordinary noise does not average out when you sum distances: every segment picks up the
/// error of both its endpoints, always as a positive contribution (|d| ≥ 0), so the total
/// only ever grows. Measured on the test fixture, a 1 000 m drive with σ = 8 m fixes sums to
/// **1 749 m** by naive fix-to-fix addition — 75 % of pure invention, in the user's favour,
/// on a document sent to a tax authority. An α-β tracker (constant-velocity model) cuts that
/// to about +2 %, and because it is seeded from the first two fixes it has **no lag on clean
/// data** — the noiseless fixture still measures 998.9 m.
struct LocationFilter {
    private(set) var totalDistanceMeters: Double
    /// Seconds of driving the filter refused to reconstruct, summed over the trip.
    ///
    /// A silence too long to bridge is not counted — inventing a straight line across ten
    /// minutes would put kilometres the user never drove on a tax document. But saying
    /// nothing about it is its own fault: the driver sees a trip that is short and has no way
    /// to know why. This is what lets the app tell them, and lets them correct the distance
    /// by hand.
    private(set) var unbridgedGapSeconds: TimeInterval = 0
    let config: FilterConfig

    // These describe the algorithm rather than policy, so they are not in FilterConfig.
    //
    // alpha/beta: tuned by simulation over 10 noise seeds, a curved 20 km route and a
    // roundabout fixture. 0.25/0.03 keeps every case inside ±4 % and costs nothing on clean
    // data. Lower alpha filters noise better but overshoots sharp turns; higher tracks turns
    // but lets noise through.
    private static let smoothingAlpha = 0.25
    private static let smoothingBeta = 0.03
    /// A segment shorter than the fix's own uncertainty cannot be told apart from noise.
    /// Spec §4 says `accuracy × 0.5`, which is *below* the noise it is meant to reject; ×2
    /// is what actually holds the error down (measured: +3.9 % worst case instead of +5.6 %).
    private static let minimumSegmentMeters: Double = 10
    private static let noiseFloorAccuracyFactor: Double = 2
    /// Below this, a silence is just a slow update, not a tunnel.
    private static let bridgeMinGap: TimeInterval = 20
    /// A bridged segment must be consistent with how fast the vehicle was going. The floor
    /// of 36 m/s (130 km/h) keeps a legitimate motorway tunnel entered from slow traffic
    /// from being thrown away: losing real distance is the costlier error here.
    private static let bridgeSpeedTolerance = 1.5
    private static let bridgeSpeedFloor: Double = 36

    /// Last fix that was good enough to reason from — the reference for order, speed and gaps.
    private var lastAccepted: LocationSample?
    private var lastKnownSpeed: Double = 0
    /// Where distance was last measured from: the smoothed position, not a raw fix.
    private var anchorLatitude = 0.0
    private var anchorLongitude = 0.0
    /// Origin of the local tangent plane. It is re-based onto the current estimate after
    /// every fix, so the flat-earth approximation is only ever asked to cover a few metres.
    private var frameLatitude = 0.0
    private var frameLongitude = 0.0
    /// Velocity estimate in the local frame, m/s east and north. `nil` until two fixes have
    /// been seen: seeding it from a real pair removes the start-up lag a zero seed causes.
    private var velocityEast: Double?
    private var velocityNorth: Double?
    private var stationarySince: Date?
    /// Set when a fix was refused as a GPS jump, cleared on the next resync. It blocks
    /// bridging: see the guard in `accept(_:now:)`.
    private var refusedJump = false

    init(
        config: FilterConfig = FilterConfig(),
        startingDistanceMeters: Double = 0,
        startingGapSeconds: TimeInterval = 0
    ) {
        self.config = config
        self.totalDistanceMeters = startingDistanceMeters
        self.unbridgedGapSeconds = startingGapSeconds
    }

    /// Judges one fix and, when it counts, adds its distance to the running total.
    ///
    /// - Parameter now: when the fix was *delivered*, which is what staleness is measured
    ///   against. It defaults to the current time — the live case — and is injectable so a
    ///   test can replay a recorded trip without waiting for it.
    mutating func accept(_ sample: LocationSample, now: Date = Date()) -> FilterDecision {
        // 1 — accuracy. A non-positive accuracy means the fix is invalid, not perfect.
        guard sample.horizontalAccuracy > 0, sample.horizontalAccuracy <= config.maxAccuracy else {
            return .rejected(.poorAccuracy)
        }

        // 2 — staleness, and only for the opening fix.
        //
        // CoreLocation replays a cached position on the first callback, which would anchor
        // the trip wherever the phone last had a signal. That is the fault this rule exists
        // for. Applying it to every fix cost real distance instead: iOS batches updates when
        // the app has been in the background, and every fix in the batch but the last is
        // older than 30 s by the time it is handed over — all of them refused, and a drive
        // recorded through a locked screen came out a fraction of its length. Fixes that
        // arrive late but *in order* describe positions the vehicle genuinely occupied; the
        // order, speed and gap rules below are what judge them.
        guard let previous = lastAccepted else {
            guard now.timeIntervalSince(sample.timestamp) <= config.maxStaleness else {
                return .rejected(.stale)
            }
            begin(at: sample)
            return .accepted(distanceMeters: 0)
        }

        // Equal timestamps are duplicates, and dividing by that zero is how a distance
        // becomes `inf`.
        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return .rejected(.outOfOrder) }

        let straightLine = Geodesy.distance(from: previous, to: sample)
        let impliedSpeed = straightLine / elapsed

        // 5a — silence too long to reconstruct. The vehicle really did drive somewhere; we
        // simply do not know how far, and an invented figure is worse than a missing one.
        guard elapsed <= config.tunnelBridgeMaxGap else {
            unbridgedGapSeconds += elapsed
            resync(to: sample)
            return .rejected(.gapTooLong)
        }

        // 3 — implausible jump. The anchor is deliberately left where it was: the vehicle is
        // almost certainly still near it, and the next good fix should measure from there.
        guard impliedSpeed <= config.maxSpeed else {
            refusedJump = true
            return .rejected(.implausibleSpeed)
        }

        // 6 — stop detection. The receiver's own speed is Doppler-derived and far better
        // than differentiating two positions, so it is preferred when present.
        let observedSpeed = sample.speed >= 0 ? sample.speed : impliedSpeed
        if observedSpeed < config.stopSpeed {
            if stationarySince == nil { stationarySince = sample.timestamp }
            // Kill the velocity estimate the moment the vehicle is known to be stopped.
            // Without this the constant-velocity model keeps coasting into the noise cloud
            // and invents distance while parked — measured at +177 m over a 3 min stop.
            velocityEast = 0
            velocityNorth = 0
            if sample.timestamp.timeIntervalSince(stationarySince ?? sample.timestamp) > config.stopDuration {
                _ = smooth(sample, elapsed: elapsed)  // stay in step with the fixes
                lastAccepted = sample
                lastKnownSpeed = observedSpeed
                return .paused
            }
        } else {
            stationarySince = nil
        }

        // 5b — bridgeable silence: short enough, and the straight line across it matches how
        // fast the vehicle was going when it went quiet.
        if elapsed > Self.bridgeMinGap {
            // A silence while the vehicle is standing still is a parked phone, not a tunnel.
            //
            // Bridging it was the single largest source of invented distance in this app: the
            // straight line is added at full value — the noise floor below is bypassed
            // entirely — and `resync` cleared the stop counter, so the 120 s pause was never
            // reached and every drifting fix bridged again. Measured at +2.6 km over a
            // 30 minute stop in a basement car park, on a document sent to a tax authority.
            //
            // The stop counter is deliberately left alone here: it is what lets step 6 reach
            // `.paused` on a later fix.
            guard observedSpeed >= config.stopSpeed else {
                lastAccepted = sample
                lastKnownSpeed = observedSpeed
                return .rejected(.belowNoiseFloor)
            }
            // Bridging is for *silence*. A receiver that was talking the whole time and had
            // every word refused as a jump is a receiver we do not believe, and believing
            // its geometry later — once enough time has passed for the implied speed to look
            // reasonable — would hand the user kilometres they never drove. Rejoin the fix,
            // count nothing.
            guard !refusedJump else {
                unbridgedGapSeconds += elapsed
                resync(to: sample)
                return .rejected(.gapTooLong)
            }
            let plausible = max(lastKnownSpeed * Self.bridgeSpeedTolerance, Self.bridgeSpeedFloor)
            guard impliedSpeed <= plausible else {
                refusedJump = true
                return .rejected(.implausibleSpeed)
            }
            totalDistanceMeters += straightLine
            resync(to: sample)
            return .bridged(distanceMeters: straightLine)
        }

        let estimate = smooth(sample, elapsed: elapsed)
        let travelled = Geodesy.distance(
            fromLatitude: anchorLatitude, longitude: anchorLongitude,
            toLatitude: estimate.latitude, longitude: estimate.longitude
        )
        lastAccepted = sample
        lastKnownSpeed = observedSpeed

        // 4 — noise floor. Keeping the anchor put is the point: short hops are not thrown
        // away, they accumulate until they add up to a real move.
        let noiseFloor = max(
            Self.minimumSegmentMeters,
            sample.horizontalAccuracy * Self.noiseFloorAccuracyFactor
        )
        guard travelled > noiseFloor else { return .rejected(.belowNoiseFloor) }

        totalDistanceMeters += travelled
        anchorLatitude = estimate.latitude
        anchorLongitude = estimate.longitude
        return .accepted(distanceMeters: travelled)
    }

    // MARK: - Internals

    private mutating func begin(at sample: LocationSample) {
        lastAccepted = sample
        anchorLatitude = sample.latitude
        anchorLongitude = sample.longitude
        frameLatitude = sample.latitude
        frameLongitude = sample.longitude
        velocityEast = nil
        velocityNorth = nil
        lastKnownSpeed = max(sample.speed, 0)
        stationarySince = (sample.speed >= 0 && sample.speed < config.stopSpeed)
            ? sample.timestamp : nil
        refusedJump = false
    }

    /// Drops the estimator onto a raw fix: used after a gap, where the track between the two
    /// is unknown and any smoothed continuation would be fiction.
    private mutating func resync(to sample: LocationSample) {
        lastAccepted = sample
        anchorLatitude = sample.latitude
        anchorLongitude = sample.longitude
        frameLatitude = sample.latitude
        frameLongitude = sample.longitude
        velocityEast = nil
        velocityNorth = nil
        lastKnownSpeed = max(sample.speed, 0)
        stationarySince = nil
        refusedJump = false
    }

    /// One α-β update, returning the filtered position.
    ///
    /// The tangent plane is re-centred on the previous estimate before every update, so the
    /// previous estimate is the origin and the prediction is simply velocity × elapsed.
    private mutating func smooth(
        _ sample: LocationSample,
        elapsed: TimeInterval
    ) -> (latitude: Double, longitude: Double) {
        let measured = Geodesy.project(
            latitude: sample.latitude, longitude: sample.longitude,
            originLatitude: frameLatitude, originLongitude: frameLongitude
        )
        let x: Double
        let y: Double
        if let east = velocityEast, let north = velocityNorth {
            let predictedX = east * elapsed
            let predictedY = north * elapsed
            let residualX = measured.x - predictedX
            let residualY = measured.y - predictedY
            x = predictedX + Self.smoothingAlpha * residualX
            y = predictedY + Self.smoothingAlpha * residualY
            velocityEast = east + Self.smoothingBeta * residualX / elapsed
            velocityNorth = north + Self.smoothingBeta * residualY / elapsed
        } else {
            // Two-point seed: take the fix as-is and let the pair define the velocity.
            velocityEast = measured.x / elapsed
            velocityNorth = measured.y / elapsed
            x = measured.x
            y = measured.y
        }
        let position = Geodesy.unproject(
            x: x, y: y, originLatitude: frameLatitude, originLongitude: frameLongitude
        )
        frameLatitude = position.latitude
        frameLongitude = position.longitude
        return position
    }
}
