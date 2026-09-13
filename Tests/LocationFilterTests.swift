import XCTest
@testable import MileagePocket

/// The distance a user claims is whatever this filter says it is, so every rule gets a test
/// with a known ground truth — and the boundary rules get tested *on* the boundary, not near
/// it.
final class LocationFilterTests: XCTestCase {

    /// Feeds a trace as if each fix were delivered the instant it was produced, which is the
    /// live case; staleness is exercised separately by moving `now` on purpose.
    @discardableResult
    private func feed(_ samples: [LocationSample], into filter: inout LocationFilter) -> [FilterDecision] {
        var decisions: [FilterDecision] = []
        for sample in samples {
            decisions.append(filter.accept(sample, now: sample.timestamp))
        }
        return decisions
    }

    // MARK: - 1. Clean straight line

    func testCleanStraightLineMeasuresItsTrueLength() {
        var filter = LocationFilter()
        let line = RouteFixtures.straightLine()
        feed(line, into: &filter)

        XCTAssertEqual(
            filter.totalDistanceMeters, 1_000, accuracy: 20,
            "a noiseless 1 000 m line must measure 1 000 m to within 2 %"
        )
    }

    // MARK: - 2. Noisy straight line — and proof the filter is what saves it

    func testNoisyStraightLineStaysWithinFivePercentWhereRawSummingDoesNot() {
        let noisy = RouteFixtures.noised(
            RouteFixtures.straightLine(), sigmaMeters: 8, reportedAccuracy: 8, seed: 42
        )

        // Without this assertion the test would pass just as well with no filter at all.
        let rawSum = RouteFixtures.rawSumOfDistances(noisy)
        XCTAssertGreaterThan(
            rawSum, 1_200,
            "the fixture must actually be hostile: naive fix-to-fix summing has to blow past 1 200 m"
        )

        var filter = LocationFilter()
        feed(noisy, into: &filter)

        XCTAssertEqual(
            filter.totalDistanceMeters, 1_000, accuracy: 50,
            "σ = 8 m noise must still measure 1 000 m to within 5 % (raw sum was \(Int(rawSum)) m)"
        )
    }

    // MARK: - 3. Poor accuracy

    func testFixWithPoorAccuracyIsRejectedAndCostsNoDistance() {
        var filter = LocationFilter()
        let line = RouteFixtures.straightLine()
        feed(Array(line.prefix(3)), into: &filter)
        let before = filter.totalDistanceMeters

        let wild = LocationSample(
            latitude: line[3].latitude, longitude: line[3].longitude,
            horizontalAccuracy: 120, altitude: 35, speed: 10, timestamp: line[3].timestamp
        )
        XCTAssertEqual(filter.accept(wild, now: wild.timestamp), .rejected(.poorAccuracy))
        XCTAssertEqual(filter.totalDistanceMeters, before, "a rejected fix must not move the total")
    }

    // MARK: - 4. Implausible speed

    func testFiveKilometreJumpInTwoSecondsIsRejected() {
        var filter = LocationFilter()
        let line = RouteFixtures.straightLine()
        feed(Array(line.prefix(3)), into: &filter)
        let before = filter.totalDistanceMeters

        let jumped = RouteFixtures.withOutlierJump(line, atIndex: 3, metersEast: 5_000)[3]
        let twoSecondsLater = LocationSample(
            latitude: jumped.latitude, longitude: jumped.longitude,
            horizontalAccuracy: 5, altitude: 35, speed: 10,
            timestamp: line[2].timestamp.addingTimeInterval(2)
        )
        XCTAssertEqual(
            filter.accept(twoSecondsLater, now: twoSecondsLater.timestamp),
            .rejected(.implausibleSpeed)
        )
        XCTAssertEqual(filter.totalDistanceMeters, before)
    }

    // MARK: - 5. Out of order

    func testFixOlderThanTheLastAcceptedOneIsRejected() {
        var filter = LocationFilter()
        let line = RouteFixtures.straightLine()
        feed(Array(line.prefix(4)), into: &filter)
        let before = filter.totalDistanceMeters

        let backwards = LocationSample(
            latitude: line[4].latitude, longitude: line[4].longitude,
            horizontalAccuracy: 5, altitude: 35, speed: 10,
            timestamp: line[1].timestamp  // earlier than the last accepted fix
        )
        XCTAssertEqual(
            filter.accept(backwards, now: line[4].timestamp),
            .rejected(.outOfOrder)
        )
        XCTAssertEqual(filter.totalDistanceMeters, before)
    }

    func testACachedFixOnTheOpeningCallbackIsRejectedAsStale() {
        var filter = LocationFilter()
        let sample = RouteFixtures.straightLine()[0]

        // CoreLocation hands out a cached fix on the first callback. Counting it anchors the
        // trip wherever the phone last had a signal, and the first real fix then measures a
        // straight line across the whole gap between the two.
        XCTAssertEqual(
            filter.accept(sample, now: sample.timestamp.addingTimeInterval(31)),
            .rejected(.stale)
        )
        XCTAssertEqual(filter.totalDistanceMeters, 0)
    }

    /// iOS batches location updates while the app is in the background, then hands the whole
    /// batch over at once: every fix in it but the last is already older than the staleness
    /// window by the time it arrives. Refusing them threw away the distance of a drive
    /// recorded through a locked screen — which is the app's entire job.
    func testABatchDeliveredLateStillCountsEveryFixInIt() {
        // Ten minutes of driving, handed over in one batch when the app comes back to the
        // foreground. Sized deliberately: with staleness applied to every fix, everything
        // older than the window is refused and the first survivor lands more than
        // `tunnelBridgeMaxGap` after the anchor, so the silence is unbridgeable and nine
        // tenths of the drive is gone. Only the last 25 s of it would be counted.
        let line = RouteFixtures.straightLine(pointCount: 400, stepMeters: 25, speedMetersPerSecond: 25)
        var filter = LocationFilter()

        _ = filter.accept(line[0], now: line[0].timestamp)
        let deliveredAt = line[line.count - 1].timestamp.addingTimeInterval(5)
        for sample in line.dropFirst() {
            _ = filter.accept(sample, now: deliveredAt)
        }

        // 399 steps of 25 m.
        XCTAssertEqual(
            filter.totalDistanceMeters, 9_975, accuracy: 150,
            "a batch delivered after the fact describes real positions and must be counted"
        )
        XCTAssertEqual(
            filter.unbridgedGapSeconds, 0,
            "nothing was actually missing — the fixes were merely handed over late"
        )
    }

    // MARK: - 6. Tunnel bridged

    func testSixtySecondTunnelIsBridgedAndItsDistanceCounted() {
        let line = RouteFixtures.straightLine(
            pointCount: 200, stepMeters: 25, speedMetersPerSecond: 25
        )
        let withTunnel = RouteFixtures.withGap(line, startingAtIndex: 50, seconds: 60)

        var filter = LocationFilter()
        let decisions = feed(withTunnel, into: &filter)

        let bridged = decisions.compactMap { decision -> Double? in
            if case .bridged(let meters) = decision { return meters }
            return nil
        }
        XCTAssertEqual(bridged.count, 1, "exactly one segment spans the tunnel")
        XCTAssertEqual(
            bridged.first ?? 0, 1_525, accuracy: 30,
            "61 s of tunnel at 25 m/s is about 1 525 m and must be part of the trip"
        )
        XCTAssertEqual(
            filter.totalDistanceMeters, RouteFixtures.straightLineLength(pointCount: 200, stepMeters: 25),
            accuracy: 100,
            "the tunnel must not cost the driver the distance they actually drove"
        )
    }

    // MARK: - 7. Gap too long

    func testTenMinuteGapIsNotBridgedAndItsDistanceIsNotCounted() {
        let line = RouteFixtures.straightLine(
            pointCount: 800, stepMeters: 25, speedMetersPerSecond: 25
        )
        let withHole = RouteFixtures.withGap(line, startingAtIndex: 100, seconds: 600)

        var filter = LocationFilter()
        let decisions = feed(withHole, into: &filter)

        XCTAssertEqual(
            decisions.filter { $0 == .rejected(.gapTooLong) }.count, 1,
            "the fix that lands after a 10 min silence cannot be trusted to have driven there"
        )
        // 99 steps before the hole + 99 after, 25 m each: the 15 km of unobserved driving
        // is deliberately lost rather than invented.
        XCTAssertEqual(
            filter.totalDistanceMeters, 4_950, accuracy: 100,
            "distance across an unbridgeable gap must not be counted"
        )
        // Not counting it is right; saying nothing about it is not. The driver sees a trip
        // that is 15 km short and has no way to know why, or that the distance is editable.
        XCTAssertEqual(
            filter.unbridgedGapSeconds, 600, accuracy: 1,
            "the silence that was not counted has to be reportable"
        )
    }

    func testATripWithNoGapReportsNoGap() {
        let line = RouteFixtures.straightLine(pointCount: 200, stepMeters: 25, speedMetersPerSecond: 25)
        var filter = LocationFilter()
        _ = feed(line, into: &filter)
        XCTAssertEqual(filter.unbridgedGapSeconds, 0)
    }

    func testABridgedTunnelIsNotReportedAsALostStretch() {
        let line = RouteFixtures.straightLine(
            pointCount: 400, stepMeters: 25, speedMetersPerSecond: 25
        )
        let withTunnel = RouteFixtures.withGap(line, startingAtIndex: 100, seconds: 60)

        var filter = LocationFilter()
        _ = feed(withTunnel, into: &filter)

        // It was counted, so there is nothing for the driver to correct.
        XCTAssertEqual(filter.unbridgedGapSeconds, 0)
    }

    // MARK: - 8. Stop detection

    func testThreeMinutesParkedIsPausedAndAddsNoDistance() {
        var filter = LocationFilter()
        let line = RouteFixtures.straightLine()
        feed(line, into: &filter)
        let drivenDistance = filter.totalDistanceMeters
        XCTAssertGreaterThan(drivenDistance, 900)

        let last = line[line.count - 1]
        let parked = RouteFixtures.stationary(
            pointCount: 37, intervalSeconds: 5, noiseSigma: 3,
            latitude: last.latitude, longitude: last.longitude,
            startingAt: last.timestamp.addingTimeInterval(5)
        )
        let decisions = feed(parked, into: &filter)

        XCTAssertEqual(decisions.last, .paused, "after 3 min at a standstill the trip is paused")
        XCTAssertEqual(
            filter.totalDistanceMeters, drivenDistance, accuracy: 1,
            "3 m of noise around a parked car must not become metres of claimable distance"
        )
    }

    func testAJumpTheFilterRefusedIsNeverBridgedAfterwards() {
        // A receiver stuck 5 km away keeps reporting the same wrong place. As the seconds
        // pass, the implied speed from the last good fix falls back under the cap — and a
        // filter that bridges on geometry alone would then hand the driver 5 km of expenses
        // for a car that never moved.
        let line = RouteFixtures.straightLine(pointCount: 400, stepMeters: 10)
        var filter = LocationFilter()
        _ = filter.accept(line[0], now: line[0].timestamp)
        _ = filter.accept(line[1], now: line[1].timestamp)
        let banked = filter.totalDistanceMeters

        let stuck = RouteFixtures.offset(
            latitude: line[2].latitude, longitude: line[2].longitude,
            eastMeters: 5_000, northMeters: 0
        )
        var decisions: [FilterDecision] = []
        for index in 2..<line.count {
            let sample = LocationSample(
                latitude: stuck.latitude, longitude: stuck.longitude,
                horizontalAccuracy: 5, altitude: 35, speed: 10,
                timestamp: line[index].timestamp
            )
            decisions.append(filter.accept(sample, now: sample.timestamp))
        }

        XCTAssertFalse(
            decisions.contains { if case .bridged = $0 { return true } else { return false } },
            "bridging is for silence, not for fixes we spent two minutes refusing"
        )
        XCTAssertEqual(
            filter.totalDistanceMeters, banked, accuracy: 1,
            "a receiver glitch must not turn into distance once enough time has passed"
        )
    }

    // MARK: - 9. Exact boundaries

    func testHorizontalAccuracyBoundaryIsInclusive() {
        let line = RouteFixtures.straightLine()

        func decision(forAccuracy accuracy: Double) -> FilterDecision {
            var filter = LocationFilter()
            _ = filter.accept(line[0], now: line[0].timestamp)
            // 200 m out, so the fix clears the noise floor and only accuracy is on trial.
            let point = RouteFixtures.offset(
                latitude: line[0].latitude, longitude: line[0].longitude,
                eastMeters: 200, northMeters: 0
            )
            let sample = LocationSample(
                latitude: point.latitude, longitude: point.longitude,
                horizontalAccuracy: accuracy, altitude: 35, speed: 10,
                timestamp: line[0].timestamp.addingTimeInterval(20)
            )
            return filter.accept(sample, now: sample.timestamp)
        }

        XCTAssertNotEqual(
            decision(forAccuracy: 50), .rejected(.poorAccuracy),
            "50 m accuracy is the limit and the limit is allowed"
        )
        XCTAssertEqual(
            decision(forAccuracy: 50.0001), .rejected(.poorAccuracy),
            "a hair over the limit is out"
        )
    }

    func testImpliedSpeedBoundaryIsInclusive() {
        let config = FilterConfig()
        let start = LocationSample(
            latitude: RouteFixtures.originLatitude, longitude: RouteFixtures.originLongitude,
            horizontalAccuracy: 5, altitude: 35, speed: -1, timestamp: RouteFixtures.epoch
        )
        let target = RouteFixtures.offset(
            latitude: start.latitude, longitude: start.longitude,
            eastMeters: 600, northMeters: 0
        )

        func decision(afterSeconds dt: TimeInterval) -> FilterDecision {
            var filter = LocationFilter()
            _ = filter.accept(start, now: start.timestamp)
            let sample = LocationSample(
                latitude: target.latitude, longitude: target.longitude,
                horizontalAccuracy: 5, altitude: 35, speed: -1,
                timestamp: start.timestamp.addingTimeInterval(dt)
            )
            return filter.accept(sample, now: sample.timestamp)
        }

        // Measure the segment with the code under test, so the boundary is built from the
        // very distance the speed check will divide — no second opinion, no rounding gap.
        guard case .accepted(let meters) = decision(afterSeconds: 15) else {
            return XCTFail("the calibration run must be accepted")
        }
        XCTAssertEqual(meters, 600, accuracy: 1)

        // The rule is `implied > cap`, so the boundary is proven by walking the gap one ulp
        // at a time: every implied speed at or below 60 m/s is accepted and the very first
        // one above it is rejected. Asserting on a hand-built "60.0" instead would be
        // asserting on rounding — for this segment the quotient is not representable at all,
        // the two adjacent doubles being 59.999999999999993 and 60.00000000000001.
        var dt = meters / config.maxSpeed
        var lastAcceptedSpeed = 0.0
        var steps = 0
        while meters / dt <= config.maxSpeed {
            lastAcceptedSpeed = meters / dt
            XCTAssertNotEqual(
                decision(afterSeconds: dt), .rejected(.implausibleSpeed),
                "\(lastAcceptedSpeed) m/s is at or below the cap and must be accepted"
            )
            dt = dt.nextDown
            steps += 1
            XCTAssertLessThan(steps, 64, "the crossing is a handful of ulps away, not a search")
        }
        XCTAssertEqual(
            lastAcceptedSpeed, config.maxSpeed, accuracy: 1e-12,
            "the fastest accepted implied speed is the cap itself: 216 km/h is the limit, not an error"
        )
        XCTAssertGreaterThan(meters / dt, config.maxSpeed)
        XCTAssertEqual(
            decision(afterSeconds: dt), .rejected(.implausibleSpeed),
            "the first implied speed above the cap is out"
        )

        let overCap = meters / 60.0001
        XCTAssertEqual(meters / overCap, 60.0001, accuracy: 1e-9)
        XCTAssertEqual(
            decision(afterSeconds: overCap), .rejected(.implausibleSpeed),
            "a ten-thousandth over the cap is a GPS jump, not a car"
        )
    }
}

extension LocationFilterTests {
    /// A phone parked in a basement car park, reporting a new position every 30 seconds
    /// because the receiver's own drift keeps crossing the distance filter.
    ///
    /// Every one of those gaps used to be *bridged*: the straight line was added at full
    /// value, the noise floor was skipped, and the resync cleared the stop counter so the
    /// pause was never reached. Thirty minutes of standing still produced kilometres on a
    /// tax document.
    private func stationaryDrift(
        fixes: Int,
        intervalSeconds: TimeInterval,
        driftMeters: Double,
        speed: Double
    ) -> [LocationSample] {
        let base = RouteFixtures.originLatitude
        return (0..<fixes).map { index in
            // Alternating either side of the same spot: the receiver wanders, the car does not.
            let offset = (index.isMultiple(of: 2) ? driftMeters : -driftMeters) / RouteFixtures.metersPerDegreeLatitude
            return LocationSample(
                latitude: base + offset,
                longitude: RouteFixtures.originLongitude,
                horizontalAccuracy: 20,
                altitude: 35,
                speed: speed,
                timestamp: RouteFixtures.epoch.addingTimeInterval(Double(index) * intervalSeconds)
            )
        }
    }

    func testThirtyMinutesParkedAddsNoDistance() {
        var filter = LocationFilter()
        let samples = stationaryDrift(fixes: 60, intervalSeconds: 30, driftMeters: 12, speed: 0)
        for sample in samples {
            _ = filter.accept(sample, now: sample.timestamp)
        }
        XCTAssertLessThan(
            filter.totalDistanceMeters, 50,
            "30 minutes parked must not invent distance, got \(filter.totalDistanceMeters) m"
        )
    }

    /// The stop is actually reached, rather than being reset by every bridged fix.
    func testAStationaryVehicleEventuallyReportsPaused() {
        var filter = LocationFilter()
        let samples = stationaryDrift(fixes: 20, intervalSeconds: 30, driftMeters: 12, speed: 0)
        let decisions = samples.map { filter.accept($0, now: $0.timestamp) }
        XCTAssertTrue(decisions.contains(.paused), "a vehicle standing still for 10 minutes must pause")
    }

    /// A receiver that reports no speed at all — common indoors — must not defeat the guard:
    /// the implied speed across the gap is then what says the car is not moving.
    func testDriftWithNoReportedSpeedIsAlsoRefused() {
        var filter = LocationFilter()
        let samples = stationaryDrift(fixes: 40, intervalSeconds: 30, driftMeters: 12, speed: -1)
        for sample in samples {
            _ = filter.accept(sample, now: sample.timestamp)
        }
        XCTAssertLessThan(filter.totalDistanceMeters, 50, "got \(filter.totalDistanceMeters) m")
    }

    /// The guard must not eat a real tunnel: emerging at speed after a silence still bridges.
    func testATunnelIsStillBridgedAfterTheStationaryGuard() {
        var filter = LocationFilter()
        let start = LocationSample(
            latitude: RouteFixtures.originLatitude, longitude: RouteFixtures.originLongitude,
            horizontalAccuracy: 8, altitude: 35, speed: 25,
            timestamp: RouteFixtures.epoch
        )
        _ = filter.accept(start, now: start.timestamp)

        // 60 s later, 1 500 m further on, still moving: a tunnel, not a car park.
        let exit = LocationSample(
            latitude: RouteFixtures.originLatitude + 1_500 / RouteFixtures.metersPerDegreeLatitude,
            longitude: RouteFixtures.originLongitude,
            horizontalAccuracy: 8, altitude: 35, speed: 25,
            timestamp: RouteFixtures.epoch.addingTimeInterval(60)
        )
        let decision = filter.accept(exit, now: exit.timestamp)

        guard case .bridged = decision else {
            return XCTFail("a tunnel crossed at speed must still be bridged, got \(decision)")
        }
        XCTAssertEqual(filter.totalDistanceMeters, 1_500, accuracy: 30)
    }
}
