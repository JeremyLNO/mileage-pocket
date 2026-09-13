import XCTest
@testable import MileagePocket

/// Exercises the engine's mechanics with **synthetic** packs whose numbers are invented for
/// the test and belong to no real country. The shipped packs are checked separately, against
/// their own official sources, in `RulePackTests`.
final class MileageCalculationTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    private func pack(
        country: String = "XX",
        unit: DistanceUnit = .kilometers,
        currency: String = "EUR",
        schemes: [RateScheme],
        validFrom: Date? = nil,
        validUntil: Date? = nil
    ) -> RulePack {
        RulePack(
            country: country,
            version: "2026.1",
            validFrom: validFrom ?? Date(timeIntervalSince1970: 0),
            validUntil: validUntil,
            currencyCode: currency,
            distanceUnit: unit,
            source: "Synthetic test scale",
            sourceURL: URL(string: "https://example.test/scale")!,
            lastVerified: Date(timeIntervalSince1970: 0),
            notes: nil,
            schemes: schemes
        )
    }

    private func flatScheme(_ rate: String) -> RateScheme {
        RateScheme(
            id: "car",
            vehicleTypes: VehicleType.allCases,
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: rate)!)]
        )
    }

    /// Marginal, in miles: the shape HMRC and the CRA use.
    private var marginalScheme: RateScheme {
        RateScheme(
            id: "car",
            vehicleTypes: [.car, .van, .electricCar],
            bandMode: .marginal,
            bands: [
                RateBand(fromDistance: 0, toDistance: 10_000, rate: Decimal(string: "0.45")!),
                RateBand(fromDistance: 10_000, toDistance: nil, rate: Decimal(string: "0.25")!),
            ]
        )
    }

    /// Whole-band with an additive constant: the shape of the French scale.
    private var wholeScheme: RateScheme {
        RateScheme(
            id: "car",
            vehicleTypes: VehicleType.allCases,
            bandMode: .whole,
            bands: [
                RateBand(fromDistance: 0, toDistance: 5_000, rate: Decimal(string: "0.500")!),
                RateBand(fromDistance: 5_000, toDistance: 20_000, rate: Decimal(string: "0.300")!, constant: Decimal(string: "1000")!),
                RateBand(fromDistance: 20_000, toDistance: nil, rate: Decimal(string: "0.350")!),
            ]
        )
    }

    private func amount(
        _ rule: MileageRule,
        km: Double,
        alreadyDrivenKm: Double = 0,
        vehicle: Vehicle? = nil
    ) -> Decimal {
        rule.calculate(
            distanceMeters: km * 1000,
            vehicle: vehicle,
            date: day,
            yearlyDistanceMeters: alreadyDrivenKm * 1000
        ).amount
    }

    // MARK: - Flat rate

    func testFlatRateMultipliesDistanceByRate() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [flatScheme("0.30")]))
        XCTAssertEqual(amount(rule, km: 100), Decimal(string: "30.00"))
        XCTAssertEqual(amount(rule, km: 24.3), Decimal(string: "7.29"))
    }

    func testFlatRateIgnoresDistanceAlreadyDrivenThisYear() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [flatScheme("0.30")]))
        XCTAssertEqual(amount(rule, km: 100, alreadyDrivenKm: 50_000), Decimal(string: "30.00"))
    }

    func testZeroDistanceIsWorthNothing() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [flatScheme("0.30")]))
        XCTAssertEqual(amount(rule, km: 0), 0)
        XCTAssertEqual(amount(rule, km: -5), 0, "a negative distance must not produce a negative claim")
    }

    // MARK: - Marginal bands, boundary tested on the bound itself

    func testMarginalBandBelowTheThreshold() {
        let rule = DeclarativeMileageRule(pack: pack(unit: .miles, currency: "GBP", schemes: [marginalScheme]))
        let miles = 100.0 * 1609.344
        let result = rule.calculate(distanceMeters: miles, vehicle: nil, date: day, yearlyDistanceMeters: 0)
        XCTAssertEqual(result.amount, Decimal(string: "45.00"))
        XCTAssertEqual(result.unit, .miles)
        XCTAssertEqual(result.currencyCode, "GBP")
        XCTAssertTrue(result.isOfficial)
    }

    func testMarginalTripEndingExactlyOnTheThresholdStaysInTheLowerBand() {
        let rule = DeclarativeMileageRule(pack: pack(unit: .miles, schemes: [marginalScheme]))
        let result = rule.calculate(
            distanceMeters: 100 * 1609.344,
            vehicle: nil,
            date: day,
            yearlyDistanceMeters: 9_900 * 1609.344
        )
        XCTAssertEqual(result.amount, Decimal(string: "45.00"))
    }

    func testMarginalTripStartingExactlyOnTheThresholdIsEntirelyInTheUpperBand() {
        let rule = DeclarativeMileageRule(pack: pack(unit: .miles, schemes: [marginalScheme]))
        let result = rule.calculate(
            distanceMeters: 100 * 1609.344,
            vehicle: nil,
            date: day,
            yearlyDistanceMeters: 10_000 * 1609.344
        )
        XCTAssertEqual(result.amount, Decimal(string: "25.00"))
    }

    func testMarginalTripStraddlingTheThresholdIsSplitAcrossBothRates() {
        let rule = DeclarativeMileageRule(pack: pack(unit: .miles, schemes: [marginalScheme]))
        let result = rule.calculate(
            distanceMeters: 100 * 1609.344,
            vehicle: nil,
            date: day,
            yearlyDistanceMeters: 9_950 * 1609.344
        )
        // 50 miles at 0.45 + 50 miles at 0.25
        XCTAssertEqual(result.amount, Decimal(string: "35.00"))
    }

    // MARK: - Whole-band selection with an additive constant

    func testWholeBandAppliesTheSelectedRateToTheEntireDistance() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [wholeScheme]))
        // First 1 000 km of the year: 1 000 × 0.500
        XCTAssertEqual(amount(rule, km: 1_000), Decimal(string: "500.00"))
    }

    /// Which side of 5 000 the bound falls on, asked of a scale where the two sides give
    /// different answers.
    ///
    /// The ordinary fixture is continuous at the bound — 5 000 × 0.500 and
    /// 5 000 × 0.300 + 1 000 are both 2 500 — so it cannot tell an inclusive `<=` from an
    /// exclusive `<`. Flipping `RateBand.contains` left every whole-band test in the repo
    /// green. This scale is deliberately discontinuous there.
    func testWholeBandBoundaryIsInclusiveOfTheLowerBand() {
        let discontinuous = RateScheme(
            id: "car",
            vehicleTypes: VehicleType.allCases,
            bandMode: .whole,
            bands: [
                RateBand(fromDistance: 0, toDistance: 5_000, rate: Decimal(string: "0.500")!),
                // No constant, and a far lower rate: at exactly 5 000 this line is worth
                // 1 500, against the lower line's 2 500.
                RateBand(fromDistance: 5_000, toDistance: nil, rate: Decimal(string: "0.300")!),
            ]
        )
        let rule = DeclarativeMileageRule(pack: pack(schemes: [discontinuous]))
        XCTAssertEqual(
            amount(rule, km: 5_000), Decimal(string: "2500.00"),
            "exactly 5 000 km belongs to the band that ends at 5 000, not to the one that starts there"
        )
        // And one kilometre past it does change line.
        XCTAssertEqual(amount(rule, km: 5_001), Decimal(string: "1500.30"))
    }

    func testWholeBandCrossingRepricesTheWholeYearNotJustTheExcess() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [wholeScheme]))
        // cumulative(5 500) = 5 500 × 0.300 + 1 000 = 2 650
        // cumulative(4 500) = 4 500 × 0.500         = 2 250
        XCTAssertEqual(amount(rule, km: 1_000, alreadyDrivenKm: 4_500), Decimal(string: "400.00"))
    }

    func testWholeBandConstantIsCountedOnceNotOncePerTrip() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [wholeScheme]))
        // Twelve 500 km trips must total exactly what the year's 6 000 km is worth:
        // 6 000 × 0.300 + 1 000 = 2 800.
        var total = Decimal(0)
        for index in 0..<12 {
            total += amount(rule, km: 500, alreadyDrivenKm: Double(index) * 500)
        }
        XCTAssertEqual(total, Decimal(string: "2800.00"))
    }

    func testMarginalTripsAlsoSumToTheYearsFigure() {
        let rule = DeclarativeMileageRule(pack: pack(unit: .miles, schemes: [marginalScheme]))
        var total = Decimal(0)
        for index in 0..<24 {
            total += rule.calculate(
                distanceMeters: 500 * 1609.344,
                vehicle: nil,
                date: day,
                yearlyDistanceMeters: Double(index) * 500 * 1609.344
            ).amount
        }
        // 12 000 miles: 10 000 × 0.45 + 2 000 × 0.25
        XCTAssertEqual(total, Decimal(string: "5000.00"))
    }

    // MARK: - Vehicle matching

    func testPowerBandIsSelectedFromFiscalHorsepower() {
        let scheme = RateScheme(
            id: "car",
            vehicleTypes: VehicleType.allCases,
            bandMode: .whole,
            powerBands: [
                PowerBand(minPower: nil, maxPower: 3, bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.400")!)]),
                PowerBand(minPower: 4, maxPower: 4, bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)]),
                PowerBand(minPower: 5, maxPower: nil, bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.600")!)]),
            ],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.450")!)]
        )
        let rule = DeclarativeMileageRule(pack: pack(schemes: [scheme]))

        let threeCV = Vehicle(name: "Small")
        threeCV.fiscalHorsepower = 3
        XCTAssertEqual(amount(rule, km: 100, vehicle: threeCV), Decimal(string: "40.00"))

        let fourCV = Vehicle(name: "Mid")
        fourCV.fiscalHorsepower = 4
        XCTAssertEqual(amount(rule, km: 100, vehicle: fourCV), Decimal(string: "50.00"))

        let sevenCV = Vehicle(name: "Big")
        sevenCV.fiscalHorsepower = 7
        XCTAssertEqual(amount(rule, km: 100, vehicle: sevenCV), Decimal(string: "60.00"))
    }

    func testUnknownPowerFallsBackToTheSchemesOwnBands() {
        let scheme = RateScheme(
            id: "car",
            vehicleTypes: VehicleType.allCases,
            bandMode: .whole,
            powerBands: [PowerBand(minPower: 4, maxPower: 4, bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)])],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.450")!)]
        )
        let rule = DeclarativeMileageRule(pack: pack(schemes: [scheme]))
        let unknown = Vehicle(name: "No power entered")
        XCTAssertEqual(amount(rule, km: 100, vehicle: unknown), Decimal(string: "45.00"))
        XCTAssertEqual(amount(rule, km: 100, vehicle: nil), Decimal(string: "45.00"))
    }

    func testMotorcycleSchemeIsPickedOverTheCarScheme() {
        let carScheme = RateScheme(id: "car", vehicleTypes: [.car, .van], bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.45")!)])
        let motoScheme = RateScheme(id: "moto", vehicleTypes: [.motorcycle], bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.24")!)])
        let rule = DeclarativeMileageRule(pack: pack(schemes: [carScheme, motoScheme]))

        let bike = Vehicle(name: "Bike", vehicleType: .motorcycle)
        XCTAssertEqual(amount(rule, km: 100, vehicle: bike), Decimal(string: "24.00"))

        let car = Vehicle(name: "Car", vehicleType: .car)
        XCTAssertEqual(amount(rule, km: 100, vehicle: car), Decimal(string: "45.00"))
    }

    // MARK: - Engine resolution

    func testCountryWithoutAPackFallsBackToTheCustomRuleAndSaysItIsNotOfficial() {
        let engine = CountryRuleEngine(store: RulePackStore(packs: []))
        let rule = engine.rule(
            countryCode: "ZZ",
            mode: .official,
            customRate: Decimal(string: "0.50"),
            customCurrency: "EUR",
            unit: .kilometers,
            date: day
        )
        XCTAssertFalse(rule.isOfficial)
        XCTAssertEqual(engine.effectiveMode(requested: .official, countryCode: "ZZ", on: day), .custom)
        let result = rule.calculate(distanceMeters: 100_000, vehicle: nil, date: day, yearlyDistanceMeters: 0)
        XCTAssertEqual(result.amount, Decimal(string: "50.00"))
        XCTAssertFalse(result.isOfficial)
    }

    func testAPackNotYetInForceIsNotUsed() {
        let future = pack(country: "XX", schemes: [flatScheme("0.30")], validFrom: Date(timeIntervalSince1970: 4_000_000_000))
        let engine = CountryRuleEngine(store: RulePackStore(packs: [future]))
        XCTAssertFalse(engine.hasOfficialRule(for: "XX", on: day))
        let rule = engine.rule(countryCode: "XX", mode: .official, customRate: Decimal(string: "0.10"), customCurrency: "EUR", unit: .kilometers, date: day)
        XCTAssertFalse(rule.isOfficial)
    }

    func testAnExpiredPackIsNotUsed() {
        let expired = pack(country: "XX", schemes: [flatScheme("0.30")], validUntil: Date(timeIntervalSince1970: 1_000_000_000))
        let engine = CountryRuleEngine(store: RulePackStore(packs: [expired]))
        XCTAssertFalse(engine.hasOfficialRule(for: "XX", on: day))
    }

    func testTheHighestValidVersionWins() {
        let older = RulePack(
            country: "XX", version: "2025.1", validFrom: Date(timeIntervalSince1970: 0), validUntil: nil,
            currencyCode: "EUR", distanceUnit: .kilometers, source: "old", sourceURL: URL(string: "https://example.test")!,
            lastVerified: Date(timeIntervalSince1970: 0), notes: nil, schemes: [flatScheme("0.20")]
        )
        let newer = RulePack(
            country: "XX", version: "2026.1", validFrom: Date(timeIntervalSince1970: 0), validUntil: nil,
            currencyCode: "EUR", distanceUnit: .kilometers, source: "new", sourceURL: URL(string: "https://example.test")!,
            lastVerified: Date(timeIntervalSince1970: 0), notes: nil, schemes: [flatScheme("0.30")]
        )
        let engine = CountryRuleEngine(store: RulePackStore(packs: [older, newer]))
        let rule = engine.rule(countryCode: "XX", mode: .official, customRate: nil, customCurrency: nil, unit: .kilometers, date: day)
        XCTAssertEqual(rule.version, "2026.1")
        XCTAssertEqual(rule.calculate(distanceMeters: 100_000, vehicle: nil, date: day, yearlyDistanceMeters: 0).amount, Decimal(string: "30.00"))
    }

    func testExplicitCustomModeOverridesAnAvailableOfficialPack() {
        let engine = CountryRuleEngine(store: RulePackStore(packs: [pack(country: "XX", schemes: [flatScheme("0.30")])]))
        let rule = engine.rule(countryCode: "XX", mode: .custom, customRate: Decimal(string: "0.80"), customCurrency: "EUR", unit: .kilometers, date: day)
        XCTAssertFalse(rule.isOfficial)
        XCTAssertEqual(rule.calculate(distanceMeters: 100_000, vehicle: nil, date: day, yearlyDistanceMeters: 0).amount, Decimal(string: "80.00"))
    }

    // MARK: - Rounding

    func testMoneyIsRoundedOnceAtTheEnd() {
        let rule = DeclarativeMileageRule(pack: pack(schemes: [flatScheme("0.333")]))
        // 3 × (10 km × 0.333) rounded per trip would be 3 × 3.33 = 9.99; the engine rounds
        // each trip, so this asserts the per-trip figure itself, not an accumulated one.
        XCTAssertEqual(amount(rule, km: 10), Decimal(string: "3.33"))
        XCTAssertEqual(amount(rule, km: 15), Decimal(string: "5.00"))
    }
}

extension MileageCalculationTests {
    /// The worst defect this app has had: with no vehicle recorded, the first scheme in the
    /// pack won — and in France that is the electric one, +20 %. Every French trip taken
    /// before a vehicle was added was billed 20 % high and marked official.
    func testAnUnknownVehicleIsTreatedAsACarNotAsWhateverComesFirst() {
        let electric = RateScheme(
            id: "electric", vehicleTypes: [.electricCar], rateMultiplier: Decimal(string: "1.20"),
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)]
        )
        let car = RateScheme(
            id: "car", vehicleTypes: [.car, .van],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)]
        )
        // Electric first, exactly as the French pack orders them.
        let rule = DeclarativeMileageRule(pack: pack(schemes: [electric, car]))

        XCTAssertEqual(amount(rule, km: 100, vehicle: nil), Decimal(string: "50.00"))

        let electricCar = Vehicle(name: "Tesla", vehicleType: .electricCar)
        XCTAssertEqual(amount(rule, km: 100, vehicle: electricCar), Decimal(string: "60.00"))
    }

    /// A bicycle in France, a motorcycle in Germany: the published scale covers neither, and
    /// charging them the car rate invents a figure and calls it official.
    func testAVehicleNoSchemeCoversGetsNoOfficialAmount() {
        let carOnly = RateScheme(
            id: "car", vehicleTypes: [.car, .van],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)]
        )
        let rule = DeclarativeMileageRule(pack: pack(schemes: [carOnly]))
        let bicycle = Vehicle(name: "Vélo", vehicleType: .bicycle)

        let result = rule.calculate(distanceMeters: 100_000, vehicle: bicycle, date: day, yearlyDistanceMeters: 0)
        XCTAssertEqual(result.amount, 0)
        XCTAssertFalse(result.isOfficial, "an uncovered vehicle must not be reported as an official rate")
    }

    func testFuelConstraintsStillApplyToAKnownVehicle() {
        let dieselOnly = RateScheme(
            id: "diesel", vehicleTypes: [.car], fuelTypes: [.diesel],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.400")!)]
        )
        let anyFuel = RateScheme(
            id: "any", vehicleTypes: [.car],
            bands: [RateBand(fromDistance: 0, toDistance: nil, rate: Decimal(string: "0.500")!)]
        )
        let rule = DeclarativeMileageRule(pack: pack(schemes: [dieselOnly, anyFuel]))

        let diesel = Vehicle(name: "D", vehicleType: .car)
        diesel.fuelType = .diesel
        XCTAssertEqual(amount(rule, km: 100, vehicle: diesel), Decimal(string: "40.00"))

        let petrol = Vehicle(name: "P", vehicleType: .car)
        petrol.fuelType = .petrol
        XCTAssertEqual(amount(rule, km: 100, vehicle: petrol), Decimal(string: "50.00"))
    }
}
