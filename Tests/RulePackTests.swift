import XCTest
@testable import MileagePocket

/// Checks the packs that actually ship, against figures worked out by hand from the sources
/// recorded in `docs/mileage-rules-sources.md`. `MileageCalculationTests` proves the engine's
/// mechanics on synthetic data; this file proves the data itself.
final class RulePackTests: XCTestCase {
    private var store: RulePackStore!
    private var engine: CountryRuleEngine!

    private let shippedCountries = ["FR", "US", "GB", "CA", "DE", "BE", "CH", "AU", "IE", "NL", "ES", "PT"]

    override func setUp() {
        super.setUp()
        store = RulePackStore()
        engine = CountryRuleEngine(store: store)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func amount(
        _ country: String,
        distance: Double,
        unit: DistanceUnit,
        on day: Date,
        vehicle: Vehicle? = nil,
        alreadyDriven: Double = 0
    ) throws -> Decimal {
        let pack = try XCTUnwrap(store.pack(country: country, on: day), "no pack shipped for \(country)")
        let rule = DeclarativeMileageRule(pack: pack)
        return rule.calculate(
            distanceMeters: unit.meters(fromValue: distance),
            vehicle: vehicle,
            date: day,
            yearlyDistanceMeters: unit.meters(fromValue: alreadyDriven)
        ).amount
    }

    // MARK: - Integrity of what ships

    func testEveryExpectedCountryShips() {
        XCTAssertEqual(store.availableCountries().sorted(), shippedCountries.sorted())
    }

    /// Italy is deliberately absent: its scale is per vehicle model, published weekly behind
    /// an authenticated portal, so no national rate exists to ship. It falls back to a custom
    /// rate — which is the honest outcome, not a gap.
    func testItalyIsNotClaimedAsOfficial() {
        XCTAssertFalse(engine.hasOfficialRule(for: "IT", on: date(2026, 9, 12)))
        XCTAssertEqual(engine.effectiveMode(requested: .official, countryCode: "IT", on: date(2026, 9, 12)), .custom)
    }

    func testEveryPackCitesAVerifiedHTTPSSource() throws {
        let today = date(2026, 9, 12)
        for country in shippedCountries {
            let pack = try XCTUnwrap(store.pack(country: country, on: today), country)
            XCTAssertEqual(pack.sourceURL.scheme, "https", country)
            XCTAssertFalse(pack.source.isEmpty, country)
            XCTAssertLessThanOrEqual(pack.lastVerified, today, "\(country) claims to be verified in the future")
            XCTAssertFalse(pack.schemes.isEmpty, country)
            for scheme in pack.schemes {
                XCTAssertFalse(scheme.bands.isEmpty, "\(country)/\(scheme.id)")
                XCTAssertEqual(scheme.bands.first?.fromDistance, 0, "\(country)/\(scheme.id) must start at zero")
                XCTAssertNil(scheme.bands.last?.toDistance, "\(country)/\(scheme.id) must end open")
            }
        }
    }

    // MARK: - Flat rates

    func testUnitedStatesFlatRate() throws {
        // IRS standard mileage rate, business use, 1 July – 31 Dec 2026: 76 ¢/mile.
        XCTAssertEqual(try amount("US", distance: 100, unit: .miles, on: date(2026, 9, 12)), Decimal(string: "76.00"))
    }

    /// The US rate changed mid-year. The pack only claims the second half, so a trip taken in
    /// March must not be priced with it — the app refuses rather than applying the wrong rate.
    func testUnitedStatesPackDoesNotApplyBeforeItsValidityWindow() {
        XCTAssertNil(store.pack(country: "US", on: date(2026, 3, 1)))
        XCTAssertFalse(engine.hasOfficialRule(for: "US", on: date(2026, 3, 1)))
    }

    func testGermanyFlatRate() throws {
        XCTAssertEqual(try amount("DE", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "30.00"))
    }

    func testNetherlandsFlatRate() throws {
        XCTAssertEqual(try amount("NL", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "25.00"))
    }

    func testSpainFlatRate() throws {
        XCTAssertEqual(try amount("ES", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "26.00"))
    }

    func testPortugalFlatRate() throws {
        XCTAssertEqual(try amount("PT", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "40.00"))
    }

    func testSwitzerlandFlatRate() throws {
        XCTAssertEqual(try amount("CH", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "75.00"))
    }

    func testAustraliaFlatRate() throws {
        XCTAssertEqual(try amount("AU", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "91.00"))
    }

    // MARK: - Tiered, marginal

    func testUnitedKingdomFirstTier() throws {
        XCTAssertEqual(try amount("GB", distance: 100, unit: .miles, on: date(2026, 9, 12)), Decimal(string: "55.00"))
    }

    func testUnitedKingdomFullYearAcrossBothTiers() throws {
        // 10 000 × 55p + 2 000 × 25p
        XCTAssertEqual(
            try amount("GB", distance: 12_000, unit: .miles, on: date(2026, 9, 12)),
            Decimal(string: "6000.00")
        )
    }

    func testUnitedKingdomThresholdOnTheBoundItself() throws {
        let day = date(2026, 9, 12)
        // Exactly 10 000 miles: still entirely at the first rate.
        XCTAssertEqual(try amount("GB", distance: 10_000, unit: .miles, on: day), Decimal(string: "5500.00"))
        // One mile past a full 10 000 already driven: the new mile is at the second rate.
        XCTAssertEqual(
            try amount("GB", distance: 1, unit: .miles, on: day, alreadyDriven: 10_000),
            Decimal(string: "0.25")
        )
    }

    func testUnitedKingdomMotorcycleUsesItsOwnScheme() throws {
        let motorcycle = Vehicle(name: "Bike", vehicleType: .motorcycle)
        XCTAssertEqual(
            try amount("GB", distance: 100, unit: .miles, on: date(2026, 9, 12), vehicle: motorcycle),
            Decimal(string: "24.00")
        )
    }

    func testCanadaAcrossBothTiers() throws {
        // 5 000 × 0.73 + 1 000 × 0.67
        XCTAssertEqual(
            try amount("CA", distance: 6_000, unit: .kilometers, on: date(2026, 9, 12)),
            Decimal(string: "4320.00")
        )
    }

    // MARK: - France: whole-band selection, power bands, electric uplift

    private func frenchCar(fiscalHorsepower: Int, type: VehicleType = .car) -> Vehicle {
        let vehicle = Vehicle(name: "Test", vehicleType: type)
        vehicle.fiscalHorsepower = fiscalHorsepower
        return vehicle
    }

    func testFranceFirstBandFiveHorsepower() throws {
        // 1 000 km × 0,636
        XCTAssertEqual(
            try amount("FR", distance: 1_000, unit: .kilometers, on: date(2026, 6, 1), vehicle: frenchCar(fiscalHorsepower: 5)),
            Decimal(string: "636.00")
        )
    }

    func testFranceSecondBandAppliesToTheWholeYearPlusItsConstant() throws {
        // 10 000 km × 0,357 + 1 395 — the second line prices every kilometre, not the excess.
        XCTAssertEqual(
            try amount("FR", distance: 10_000, unit: .kilometers, on: date(2026, 6, 1), vehicle: frenchCar(fiscalHorsepower: 5)),
            Decimal(string: "4965.00")
        )
    }

    /// The published French scale is continuous at 5 000 km — the two formulas agree there.
    /// If they did not, a driver would gain or lose money by driving one more kilometre.
    func testFranceIsContinuousAtTheFiveThousandKilometreBound() throws {
        let day = date(2026, 6, 1)
        let vehicle = frenchCar(fiscalHorsepower: 5)
        let atBound = try amount("FR", distance: 5_000, unit: .kilometers, on: day, vehicle: vehicle)
        XCTAssertEqual(atBound, Decimal(string: "3180.00"))

        let oneMore = try amount("FR", distance: 1, unit: .kilometers, on: day, vehicle: vehicle, alreadyDriven: 5_000)
        XCTAssertEqual(oneMore, Decimal(string: "0.36"), "crossing the bound must not jump")
    }

    func testFranceBandsByFiscalHorsepower() throws {
        let day = date(2026, 6, 1)
        XCTAssertEqual(
            try amount("FR", distance: 1_000, unit: .kilometers, on: day, vehicle: frenchCar(fiscalHorsepower: 3)),
            Decimal(string: "529.00")
        )
        XCTAssertEqual(
            try amount("FR", distance: 1_000, unit: .kilometers, on: day, vehicle: frenchCar(fiscalHorsepower: 7)),
            Decimal(string: "697.00")
        )
    }

    /// The French rule raises the standard scale by 20 % for fully electric cars. The pack
    /// stores the published multiplier rather than a table of derived rates nobody published.
    func testFranceElectricUpliftIsTwentyPercent() throws {
        let day = date(2026, 6, 1)
        let petrol = try amount("FR", distance: 1_000, unit: .kilometers, on: day, vehicle: frenchCar(fiscalHorsepower: 5))
        let electric = try amount(
            "FR", distance: 1_000, unit: .kilometers, on: day,
            vehicle: frenchCar(fiscalHorsepower: 5, type: .electricCar)
        )
        // Fixed, not recomputed with the implementation's own formula: an assertion built
        // from the code under test agrees with it whatever it does.
        XCTAssertEqual(electric, Decimal(string: "763.20"))
    }

    // MARK: - Ireland bands by engine capacity, not horsepower

    /// Each of the three Irish displacement tiers, on its own value.
    ///
    /// This used to assert only `> 0` on a 1 400 cm³ car — and the pack's fallback bands are
    /// identical, to the character, to the 1 201–1 500 tier that car lands in. So the three
    /// tiers agreed with each other by accident: ignoring `powerBands` entirely, or reading
    /// fiscal horsepower where the scale means displacement, both left this green. The rates
    /// themselves were verified by nothing.
    func testIrelandBandsByEngineCapacity() throws {
        let day = date(2026, 9, 12)

        func amountFor(engineCapacity: Int) throws -> Decimal {
            let vehicle = Vehicle(name: "Test", vehicleType: .car)
            vehicle.engineCapacity = engineCapacity
            return try amount("IE", distance: 1_000, unit: .kilometers, on: day, vehicle: vehicle)
        }

        // 1 000 km, all inside the first marginal band of each tier.
        XCTAssertEqual(try amountFor(engineCapacity: 900), Decimal(string: "418.00"), "≤ 1 200 cm³ at 0.4180")
        XCTAssertEqual(try amountFor(engineCapacity: 1_400), Decimal(string: "434.00"), "1 201–1 500 cm³ at 0.4340")
        XCTAssertEqual(try amountFor(engineCapacity: 2_000), Decimal(string: "518.20"), "≥ 1 501 cm³ at 0.5182")
    }

    /// A vehicle that declares only fiscal horsepower must not be banded by it here: the
    /// Irish scale measures displacement, and reading the wrong figure silently picks the
    /// wrong band. Asserted at 900 — where the tier and the fallback genuinely differ, which
    /// 1 400 did not.
    func testIrelandIgnoresFiscalHorsepowerWhenTheScaleMeansDisplacement() throws {
        let day = date(2026, 9, 12)
        let wrongFigure = Vehicle(name: "Test", vehicleType: .car)
        wrongFigure.fiscalHorsepower = 900

        let fallback = try amount("IE", distance: 1_000, unit: .kilometers, on: day, vehicle: wrongFigure)
        let noVehicle = try amount("IE", distance: 1_000, unit: .kilometers, on: day, vehicle: nil)

        XCTAssertEqual(fallback, noVehicle, "an unknown displacement must fall back, not guess")
        XCTAssertEqual(
            fallback, Decimal(string: "434.00"),
            "the fallback is the pack's own default band — not the 900 cm³ tier read off the wrong field"
        )
    }

    func testIrelandPowerUnitIsEngineCapacity() throws {
        let pack = try XCTUnwrap(store.pack(country: "IE", on: date(2026, 9, 12)))
        let banded = try XCTUnwrap(pack.schemes.first { $0.powerBands?.isEmpty == false })
        XCTAssertEqual(banded.powerUnit, .engineCapacity)
    }

    func testFrancePowerUnitIsFiscalHorsepower() throws {
        let pack = try XCTUnwrap(store.pack(country: "FR", on: date(2026, 6, 1)))
        let banded = try XCTUnwrap(pack.schemes.first { $0.powerBands?.isEmpty == false })
        XCTAssertEqual(banded.powerUnit, .fiscalHorsepower)
    }

    // MARK: - Belgium's quarterly window

    func testBelgiumPackDeclaresItsExpiry() throws {
        // The Belgian rate is revised quarterly; the pack must not silently outlive its own
        // window and keep pricing trips at a stale rate.
        let pack = try XCTUnwrap(store.pack(country: "BE", on: date(2026, 9, 12)))
        XCTAssertNotNil(pack.validUntil, "a quarterly rate must carry an end date")
        XCTAssertEqual(try amount("BE", distance: 100, unit: .kilometers, on: date(2026, 9, 12)), Decimal(string: "44.40"))
    }
}

extension RulePackTests {
    /// Against the real French pack, where the electric scheme is listed first.
    func testFranceWithNoVehicleUsesTheCarScaleNotTheElectricOne() throws {
        let day = date(2026, 6, 1)
        let noVehicle = try amount("FR", distance: 1_000, unit: .kilometers, on: day, vehicle: nil)
        let plainCar = try amount(
            "FR", distance: 1_000, unit: .kilometers, on: day,
            vehicle: Vehicle(name: "Car", vehicleType: .car)
        )
        XCTAssertEqual(noVehicle, plainCar, "an unrecorded vehicle must be priced as a car")

        let electric = try amount(
            "FR", distance: 1_000, unit: .kilometers, on: day,
            vehicle: Vehicle(name: "EV", vehicleType: .electricCar)
        )
        XCTAssertEqual(
            electric, MileageRounding.money(plainCar * Decimal(string: "1.20")!),
            "the +20 % uplift belongs to electric cars and to nothing else"
        )
        XCTAssertNotEqual(noVehicle, electric)
    }

    /// A bicycle is not in the French scale. Charging it the car rate invents a figure.
    func testFranceGivesNoOfficialAmountForABicycle() throws {
        let pack = try XCTUnwrap(store.pack(country: "FR", on: date(2026, 6, 1)))
        let rule = DeclarativeMileageRule(pack: pack)
        let bicycle = Vehicle(name: "Vélo", vehicleType: .bicycle)

        let result = rule.calculate(
            distanceMeters: 100_000, vehicle: bicycle,
            date: date(2026, 6, 1), yearlyDistanceMeters: 0
        )
        XCTAssertFalse(result.isOfficial)
        XCTAssertEqual(result.amount, 0)
    }

    /// The British scale covers bicycles, so this one must stay official — the guard above
    /// must not become "anything unusual is unsupported".
    func testBritainDoesCoverBicycles() throws {
        let pack = try XCTUnwrap(store.pack(country: "GB", on: date(2026, 9, 12)))
        let rule = DeclarativeMileageRule(pack: pack)
        let bicycle = Vehicle(name: "Bike", vehicleType: .bicycle)

        let result = rule.calculate(
            distanceMeters: DistanceUnit.miles.meters(fromValue: 100), vehicle: bicycle,
            date: date(2026, 9, 12), yearlyDistanceMeters: 0
        )
        XCTAssertTrue(result.isOfficial)
        XCTAssertEqual(result.amount, Decimal(string: "20.00"))
    }
}
