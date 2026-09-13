import Foundation

/// What a place is called, at two levels of precision.
struct PlaceLabel: Equatable, Sendable {
    /// "12 Avenue Gambetta" — nil on a motorway or in open country.
    let street: String?
    /// "Courbevoie" — nil offshore or where no locality is known.
    let town: String?

    var isEmpty: Bool { street == nil && town == nil }
}

/// Names the two ends of a trip.
///
/// The right level of detail depends on the trip, which is why this is a decision and not a
/// formatting detail:
///
/// - Two different towns already say everything — "Paris → Versailles". Adding the streets
///   makes the row longer and truncates without telling anyone anything more.
/// - The same town at both ends says nothing at all — "Paris → Paris" is the label a local
///   round of client visits gets, and it is useless. There, the street is the only thing that
///   distinguishes one trip from the next.
///
/// A long drive that starts and ends in the same town (a big city loop) is the exception to
/// the exception: the street is noise at that scale, so distance overrides.
enum TripEndpointLabel {
    /// Above this, a trip is "long" and its towns alone are enough.
    static let longTripThresholdMeters: Double = 40_000

    static func format(
        start: PlaceLabel,
        end: PlaceLabel,
        distanceMeters: Double
    ) -> (start: String, end: String) {
        let sameTown = start.town != nil && start.town == end.town
        let wantsStreet = sameTown && distanceMeters < longTripThresholdMeters

        return (
            label(for: start, withStreet: wantsStreet),
            label(for: end, withStreet: wantsStreet)
        )
    }

    private static func label(for place: PlaceLabel, withStreet: Bool) -> String {
        if withStreet, let street = place.street {
            // The town is dropped here, not repeated: both ends carry the same one, and
            // "Rue X, Paris → Rue Y, Paris" spends half the row saying "Paris" twice.
            return street
        }
        if let town = place.town { return town }
        if let street = place.street { return street }
        return "—"
    }
}
