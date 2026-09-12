import Foundation
@testable import MileagePocket

/// Synthetic GPS traces with a *known* ground truth, so the distance maths can be judged
/// against a number rather than against itself.
///
/// Everything here is deterministic: the noise comes from a seeded LCG, never from
/// `Double.random`, so a failure is always reproducible and a passing run is not luck.
enum RouteFixtures {

    // Paris, Place du Châtelet-ish. Any mid-latitude origin would do; a real one keeps the
    // longitude/latitude scale ratio realistic (cos φ ≈ 0.66 here).
    static let originLatitude = 48.8566
    static let originLongitude = 2.3522

    /// Fixed epoch for every fixture. `timeIntervalSinceReferenceDate == 0` matters: the
    /// boundary tests need `t1 - t0` to be exact in binary, which it is only when one of
    /// the two is zero — at 1.7e9 the ulp is already 2.4e-7 s.
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    /// Metres per degree of latitude (WGS84 mean). Used only to *build* fixtures; the code
    /// under test measures with haversine, so a fixture built this way is an independent
    /// check of the measuring code, not a tautology.
    static let metersPerDegreeLatitude = 111_319.490_793_273_58

    static func offset(
        latitude: Double,
        longitude: Double,
        eastMeters: Double,
        northMeters: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat = latitude + northMeters / metersPerDegreeLatitude
        let lon = longitude + eastMeters / (metersPerDegreeLatitude * cos(latitude * .pi / 180))
        return (lat, lon)
    }

    // MARK: - Deterministic noise

    /// Linear congruential generator (the PCG/Knuth multiplier) plus Box–Muller.
    ///
    /// Deliberately not `SystemRandomNumberGenerator`: a GPS test that draws different
    /// noise on every run reports a different distance on every run, and then nobody can
    /// tell a regression from a bad draw.
    struct DeterministicGaussian {
        private var state: UInt64

        init(seed: UInt64) { self.state = seed }

        private mutating func nextUnitInterval() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }

        /// Standard normal, mean 0, σ 1.
        mutating func next() -> Double {
            let u1 = max(nextUnitInterval(), 1e-12)  // log(0) is -inf; clamp instead
            let u2 = nextUnitInterval()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    // MARK: - Traces

    /// A perfectly straight run: `pointCount` fixes, `stepMeters` apart, constant speed.
    ///
    /// Default: 101 points 10 m apart = exactly 1 000 m of ground truth at 10 m/s.
    static func straightLine(
        pointCount: Int = 101,
        stepMeters: Double = 10,
        bearingDegrees: Double = 45,
        speedMetersPerSecond: Double = 10,
        horizontalAccuracy: Double = 5,
        startingAt start: Date = epoch
    ) -> [LocationSample] {
        let bearing = bearingDegrees * .pi / 180
        return (0..<pointCount).map { index in
            let travelled = Double(index) * stepMeters
            let point = offset(
                latitude: originLatitude,
                longitude: originLongitude,
                eastMeters: travelled * sin(bearing),
                northMeters: travelled * cos(bearing)
            )
            return LocationSample(
                latitude: point.latitude,
                longitude: point.longitude,
                horizontalAccuracy: horizontalAccuracy,
                altitude: 35,
                speed: speedMetersPerSecond,
                timestamp: start.addingTimeInterval(travelled / speedMetersPerSecond)
            )
        }
    }

    /// The ground-truth length of `straightLine` with the given arguments.
    static func straightLineLength(pointCount: Int = 101, stepMeters: Double = 10) -> Double {
        Double(pointCount - 1) * stepMeters
    }

    /// Paris → Versailles, as a polyline of legs whose total length is known by
    /// construction (≈ 17.4 km, close to the real drive). Returned with its ground truth.
    static func parisToVersailles(
        stepMeters: Double = 20,
        speedMetersPerSecond: Double = 12.5,
        horizontalAccuracy: Double = 5,
        startingAt start: Date = epoch
    ) -> (samples: [LocationSample], distanceMeters: Double) {
        // bearing °, length m — a plausible south-west run out of Paris with real turns.
        let legs: [(Double, Double)] = [
            (250, 3_000), (200, 2_500), (265, 4_000), (190, 2_000),
            (270, 3_500), (225, 2_000), (245, 400),
        ]
        var latitude = originLatitude
        var longitude = originLongitude
        var timestamp = start
        var truth = 0.0
        var samples = [LocationSample(
            latitude: latitude, longitude: longitude,
            horizontalAccuracy: horizontalAccuracy, altitude: 35,
            speed: speedMetersPerSecond, timestamp: timestamp
        )]
        for (bearingDegrees, length) in legs {
            let bearing = bearingDegrees * .pi / 180
            for _ in 0..<Int((length / stepMeters).rounded()) {
                let point = offset(
                    latitude: latitude, longitude: longitude,
                    eastMeters: stepMeters * sin(bearing),
                    northMeters: stepMeters * cos(bearing)
                )
                latitude = point.latitude
                longitude = point.longitude
                timestamp = timestamp.addingTimeInterval(stepMeters / speedMetersPerSecond)
                truth += stepMeters
                samples.append(LocationSample(
                    latitude: latitude, longitude: longitude,
                    horizontalAccuracy: horizontalAccuracy, altitude: 35,
                    speed: speedMetersPerSecond, timestamp: timestamp
                ))
            }
        }
        return (samples, truth)
    }

    /// A vehicle parked with the engine running: the position does not move, only the noise
    /// does, and the reported speed is 0.
    static func stationary(
        pointCount: Int,
        intervalSeconds: TimeInterval,
        noiseSigma: Double,
        latitude: Double = originLatitude,
        longitude: Double = originLongitude,
        horizontalAccuracy: Double = 5,
        seed: UInt64 = 42,
        startingAt start: Date = epoch
    ) -> [LocationSample] {
        var noise = DeterministicGaussian(seed: seed)
        return (0..<pointCount).map { index in
            let east = noise.next() * noiseSigma
            let north = noise.next() * noiseSigma
            let point = offset(
                latitude: latitude, longitude: longitude,
                eastMeters: east, northMeters: north
            )
            return LocationSample(
                latitude: point.latitude, longitude: point.longitude,
                horizontalAccuracy: horizontalAccuracy, altitude: 35, speed: 0,
                timestamp: start.addingTimeInterval(Double(index) * intervalSeconds)
            )
        }
    }

    // MARK: - Degradations

    /// Adds isotropic Gaussian position error of σ = `sigmaMeters` to every fix and makes
    /// `horizontalAccuracy` tell the truth about it — which is what a real receiver does.
    static func noised(
        _ samples: [LocationSample],
        sigmaMeters: Double,
        reportedAccuracy: Double,
        seed: UInt64 = 42
    ) -> [LocationSample] {
        var noise = DeterministicGaussian(seed: seed)
        return samples.map { sample in
            let east = noise.next() * sigmaMeters
            let north = noise.next() * sigmaMeters
            let point = offset(
                latitude: sample.latitude, longitude: sample.longitude,
                eastMeters: east, northMeters: north
            )
            return LocationSample(
                latitude: point.latitude, longitude: point.longitude,
                horizontalAccuracy: reportedAccuracy, altitude: sample.altitude,
                speed: sample.speed, timestamp: sample.timestamp
            )
        }
    }

    /// Teleports one fix `metersEast` away — the classic urban-canyon reflection.
    static func withOutlierJump(
        _ samples: [LocationSample],
        atIndex index: Int,
        metersEast: Double
    ) -> [LocationSample] {
        var result = samples
        let sample = result[index]
        let point = offset(
            latitude: sample.latitude, longitude: sample.longitude,
            eastMeters: metersEast, northMeters: 0
        )
        result[index] = LocationSample(
            latitude: point.latitude, longitude: point.longitude,
            horizontalAccuracy: sample.horizontalAccuracy, altitude: sample.altitude,
            speed: sample.speed, timestamp: sample.timestamp
        )
        return result
    }

    /// Drops every fix in a `seconds`-long window: a tunnel, a car park, a dead battery in
    /// the antenna. The fixes after the hole keep their real timestamps and positions — the
    /// vehicle never stopped moving, only the receiver stopped reporting.
    static func withGap(
        _ samples: [LocationSample],
        startingAtIndex index: Int,
        seconds: TimeInterval
    ) -> [LocationSample] {
        guard samples.indices.contains(index) else { return samples }
        let gapStart = samples[index].timestamp
        let gapEnd = gapStart.addingTimeInterval(seconds)
        return samples.filter { $0.timestamp < gapStart || $0.timestamp >= gapEnd }
    }

    /// Sum of the raw fix-to-fix distances, with no filtering at all. This is the number the
    /// filter has to beat: on noisy data it is wildly inflated.
    static func rawSumOfDistances(_ samples: [LocationSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        return (1..<samples.count).reduce(0.0) { total, index in
            total + Geodesy.distance(from: samples[index - 1], to: samples[index])
        }
    }
}
