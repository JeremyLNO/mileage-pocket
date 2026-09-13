import Foundation

/// Applies a `RulePack`. This is the only calculation engine in the app: every country with
/// an official scale goes through it, so a bug here is caught by thirteen countries' worth
/// of tests instead of hiding inside one bespoke class.
///
/// The whole engine rests on one idea: a scheme defines a **cumulative** function — what the
/// year owes after driving `d` — and a trip is worth the difference that trip makes to it.
/// That single formula gets both band semantics right, splits a trip that crosses a
/// threshold exactly, and guarantees the trips of a year sum to the year's own figure.
struct DeclarativeMileageRule: MileageRule {
    let pack: RulePack

    var countryCode: String { pack.country }
    var currencyCode: String { pack.currencyCode }
    var distanceUnit: DistanceUnit { pack.distanceUnit }
    var version: String { pack.version }
    var isOfficial: Bool { true }
    var summary: String { pack.source }
    var sourceURL: URL? { pack.sourceURL }

    func calculate(
        distanceMeters: Double,
        vehicle: Vehicle?,
        date: Date,
        yearlyDistanceMeters: Double
    ) -> MileageCalculation {
        let distance = max(0, distanceMeters)
        guard distance > 0, let scheme = scheme(for: vehicle) else {
            // `isOfficial` is false here: no published scale covers this vehicle, so the
            // caller must not print this as a regulated amount.
            return MileageCalculation.zero(currencyCode: currencyCode, unit: distanceUnit)
        }

        let bands = scheme.resolvedBands(for: vehicle)
        guard !bands.isEmpty else {
            return MileageCalculation.zero(currencyCode: currencyCode, unit: distanceUnit)
        }

        let tripDistance = distanceUnit.value(fromMeters: distance)
        let alreadyDriven = distanceUnit.value(fromMeters: max(0, yearlyDistanceMeters))

        let before = cumulative(alreadyDriven, bands: bands, mode: scheme.bandMode)
        let after = cumulative(alreadyDriven + tripDistance, bands: bands, mode: scheme.bandMode)
        let exact = max(0, after - before)
        let amount = MileageRounding.money(exact)

        // Derived from `exact`, not from `amount`: dividing the rounded money by the distance
        // makes a fixed rate wobble in the last decimals from one row to the next.
        let effectiveRate = tripDistance > 0
            ? MileageRounding.rate(exact / Decimal(tripDistance))
            : 0

        return MileageCalculation(
            amount: amount,
            rate: effectiveRate,
            currencyCode: currencyCode,
            ruleVersion: pack.version,
            unit: distanceUnit,
            isOfficial: true
        )
    }

    /// The scheme that covers this vehicle, or none.
    ///
    /// There is deliberately no "first scheme" fallback. It charged a bicycle in France at
    /// the electric-car rate and a motorcycle in Germany at the car rate — an invented figure
    /// presented as the official scale. A vehicle the published scale does not cover has no
    /// official amount, and saying so is the only honest answer.
    private func scheme(for vehicle: Vehicle?) -> RateScheme? {
        pack.schemes.first { $0.matches(vehicle: vehicle) }
    }

    /// What the year owes after `distance` has been driven, in the pack's own unit.
    func cumulative(_ distance: Double, bands: [RateBand], mode: BandMode) -> Decimal {
        guard distance > 0 else { return 0 }

        switch mode {
        case .whole:
            // One band priced against the entire distance. `constant` is the scale's
            // additive term and belongs to the selected band.
            guard let band = band(containing: distance, in: bands) else { return 0 }
            return Decimal(distance) * band.rate + (band.constant ?? 0)

        case .marginal:
            var total = Decimal(0)
            var lowerBound = 0.0
            for band in bands.sorted(by: { $0.fromDistance < $1.fromDistance }) {
                let start = max(band.fromDistance, lowerBound)
                guard distance > start else { break }
                let end = min(distance, band.toDistance ?? .greatestFiniteMagnitude)
                guard end > start else { continue }
                total += Decimal(end - start) * band.rate
                lowerBound = end
            }
            return total
        }
    }

    /// Bands are written inclusive on both ends ("5 000 to 20 000"), so a distance sitting
    /// exactly on a shared bound matches the lower band first. That is the reading the
    /// published scales use, and the boundary is tested on the bound itself.
    private func band(containing distance: Double, in bands: [RateBand]) -> RateBand? {
        let sorted = bands.sorted(by: { $0.fromDistance < $1.fromDistance })
        return sorted.first { $0.contains(distance) } ?? sorted.last
    }
}
