import Foundation

/// The decoded form of one country's mileage rule pack.
///
/// Rule packs are data, not code: the three families of real-world scheme — flat rate,
/// tiered by annual distance, and banded with an additive constant — are all expressible
/// here, so adding a country is adding a JSON file, not a Swift class.
///
/// `source`, `sourceURL` and `lastVerified` are not decoration. A pack without a verified
/// official source is never shipped, and the report footer prints them so the person
/// reading the PDF can check the rule themselves.
struct RulePack: Codable, Sendable, Equatable {
    let country: String
    let version: String
    let validFrom: Date
    let validUntil: Date?
    let currencyCode: String
    let distanceUnit: DistanceUnit
    let source: String
    let sourceURL: URL
    let lastVerified: Date
    /// Optional localisation keys for country-specific caveats shown in Settings.
    let notes: [String: String]?
    let schemes: [RateScheme]

    func isValid(on date: Date) -> Bool {
        guard date >= validFrom else { return false }
        if let validUntil { return date <= validUntil }
        return true
    }
}

/// How a scheme's distance bands combine.
enum BandMode: String, Codable, Sendable {
    /// Each band charges only the distance that falls inside it. A trip crossing the
    /// threshold is charged partly at each rate. HMRC and the CRA work this way.
    case marginal
    /// One band is selected from the annual total and its rate applies to the whole
    /// distance. The French scale works this way: crossing 5 000 km re-prices every
    /// kilometre of the year, it does not add a second tier on top.
    case whole
}

/// What `powerBands` measures, which differs by country: France bands by fiscal horsepower,
/// Ireland by engine displacement. The vehicle form has to ask for the right one.
enum PowerUnit: String, Codable, Sendable {
    case fiscalHorsepower
    case engineCapacity
}

/// One set of bands, applying to a family of vehicles.
struct RateScheme: Codable, Sendable, Equatable {
    let id: String
    let vehicleTypes: [VehicleType]
    let fuelTypes: [FuelType]?
    /// Defaults to `.marginal` when the pack omits it — the commoner of the two, and the
    /// only one that makes sense for a single-band flat rate.
    let bandModeRaw: String?
    let powerUnitRaw: String?
    /// A published uplift applied to another scheme's rates, expressed as a decimal string.
    /// France's electric-vehicle rule is exactly this: the official text raises the standard
    /// scale by 20 % without publishing a second table, so the multiplier *is* the rule —
    /// storing derived rates instead would be inventing figures nobody published.
    let rateMultiplierRaw: String?
    /// Present when the rate depends on fiscal horsepower (France) or engine capacity
    /// (Ireland). When it is, `bands` still applies and is the fallback used for a vehicle
    /// whose power the user has not entered.
    let powerBands: [PowerBand]?
    let bands: [RateBand]

    private enum CodingKeys: String, CodingKey {
        case id, vehicleTypes, fuelTypes, powerBands, bands
        case bandModeRaw = "bandMode"
        case powerUnitRaw = "powerUnit"
        case rateMultiplierRaw = "rateMultiplier"
    }

    var bandMode: BandMode { bandModeRaw.flatMap(BandMode.init(rawValue:)) ?? .marginal }

    /// Defaults to fiscal horsepower: it is what the only two banded countries' users are
    /// asked for most often, and a pack that bands by displacement says so explicitly.
    var powerUnit: PowerUnit { powerUnitRaw.flatMap(PowerUnit.init(rawValue:)) ?? .fiscalHorsepower }

    var rateMultiplier: Decimal {
        guard let rateMultiplierRaw,
              let value = Decimal(string: rateMultiplierRaw, locale: Locale(identifier: "en_US_POSIX")),
              value > 0
        else { return 1 }
        return value
    }

    init(
        id: String,
        vehicleTypes: [VehicleType],
        fuelTypes: [FuelType]? = nil,
        bandMode: BandMode = .marginal,
        powerUnit: PowerUnit = .fiscalHorsepower,
        rateMultiplier: Decimal? = nil,
        powerBands: [PowerBand]? = nil,
        bands: [RateBand]
    ) {
        self.id = id
        self.vehicleTypes = vehicleTypes
        self.fuelTypes = fuelTypes
        self.bandModeRaw = bandMode.rawValue
        self.powerUnitRaw = powerUnit.rawValue
        self.rateMultiplierRaw = rateMultiplier.map { "\($0)" }
        self.powerBands = powerBands
        self.bands = bands
    }

    func matches(vehicle: Vehicle?) -> Bool {
        guard let vehicle else { return true }
        guard vehicleTypes.contains(vehicle.vehicleType) else { return false }
        if let fuelTypes, let fuel = vehicle.fuelType, !fuelTypes.contains(fuel) { return false }
        return true
    }

    /// The bands to apply to this vehicle: the matching power band when the pack has them
    /// and the vehicle declares the right kind of power, the scheme's own bands otherwise.
    func resolvedBands(for vehicle: Vehicle?) -> [RateBand] {
        let base = basePowerBands(for: vehicle)
        guard rateMultiplier != 1 else { return base }
        return base.map {
            RateBand(
                fromDistance: $0.fromDistance,
                toDistance: $0.toDistance,
                rate: $0.rate * rateMultiplier,
                constant: $0.constant.map { constant in constant * rateMultiplier }
            )
        }
    }

    private func basePowerBands(for vehicle: Vehicle?) -> [RateBand] {
        guard let powerBands, !powerBands.isEmpty else { return bands }
        // Reading the wrong figure would silently band a French car by its displacement.
        let declared: Int? = switch powerUnit {
        case .fiscalHorsepower: vehicle?.fiscalHorsepower
        case .engineCapacity: vehicle?.engineCapacity
        }
        guard let power = declared else { return bands }
        for band in powerBands where band.contains(power) {
            return band.bands
        }
        return bands
    }
}

struct PowerBand: Codable, Sendable, Equatable {
    let minPower: Int?
    let maxPower: Int?
    let bands: [RateBand]

    func contains(_ power: Int) -> Bool {
        if let minPower, power < minPower { return false }
        if let maxPower, power > maxPower { return false }
        return true
    }
}

/// A slice of the annual distance, charged at one rate.
///
/// `fromDistance`/`toDistance` are expressed in the pack's own `distanceUnit` and count
/// **cumulative distance over the tax year**, which is what tiered schemes (HMRC's 10 000
/// miles, the CRA's 5 000 km) actually measure.
struct RateBand: Codable, Sendable, Equatable {
    let fromDistance: Double
    let toDistance: Double?
    let rate: Decimal
    /// The additive term of the French scale (`amount = d × k + c`), applied once when the
    /// trip's distance falls inside this band.
    let constant: Decimal?

    init(fromDistance: Double, toDistance: Double?, rate: Decimal, constant: Decimal? = nil) {
        self.fromDistance = fromDistance
        self.toDistance = toDistance
        self.rate = rate
        self.constant = constant
    }

    private enum CodingKeys: String, CodingKey {
        case fromDistance, toDistance, rate, constant
    }

    /// Rates are written as JSON **strings**, not numbers, and parsed straight into
    /// `Decimal`. A JSON number would be routed through `Double` first, and 0.45 has no
    /// exact binary representation — the error is small per trip and compounds over a year
    /// of them, which is exactly the number a tax authority would be comparing against.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromDistance = try container.decode(Double.self, forKey: .fromDistance)
        toDistance = try container.decodeIfPresent(Double.self, forKey: .toDistance)
        rate = try Self.decimal(from: container, forKey: .rate, required: true)!
        constant = try Self.decimal(from: container, forKey: .constant, required: false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromDistance, forKey: .fromDistance)
        try container.encodeIfPresent(toDistance, forKey: .toDistance)
        try container.encode("\(rate)", forKey: .rate)
        if let constant { try container.encode("\(constant)", forKey: .constant) }
    }

    private static func decimal(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        required: Bool
    ) throws -> Decimal? {
        if let string = try container.decodeIfPresent(String.self, forKey: key) {
            guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "\(string) is not a decimal")
            }
            return value
        }
        // Tolerated so a hand-written pack with a bare number still loads rather than
        // failing the whole country; the string form stays the one we produce.
        if let number = try container.decodeIfPresent(Double.self, forKey: key) {
            return Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
        }
        if required {
            throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "missing rate"))
        }
        return nil
    }

    func contains(_ distance: Double) -> Bool {
        guard distance >= fromDistance else { return false }
        guard let toDistance else { return true }
        return distance <= toDistance
    }
}

extension RulePack {
    /// The pack files use plain `YYYY-MM-DD` dates and decimal strings, so that a pack can
    /// be read and checked by a human without running the app.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }
}
