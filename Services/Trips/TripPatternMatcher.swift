import Foundation

/// What a journey was, the last time it was driven.
///
/// The app already learns *places*; this learns *journeys*. The commute, the Tuesday client,
/// the run to the depot — they are the same two endpoints over and over, and asking what
/// they were for the fortieth time is how a mileage log stops being filled in.
///
/// Nothing is inferred and nothing is stored: the pattern is read from the trips themselves,
/// so it cannot drift away from the record it claims to summarise, and correcting one trip
/// corrects what the next one is offered.
enum TripPatternMatcher {
    /// What a matching journey says the next one probably is.
    struct Pattern: Equatable {
        let tripType: TripType
        let clientID: UUID?
        let projectID: UUID?
        let purpose: String?
        /// How many past trips ran the same route. Shown to the driver, because a
        /// suggestion that says where it comes from is one they can judge.
        let occurrences: Int
    }

    /// Both endpoints have to fall inside this. Wider than the 150 m used for a single place
    /// — a journey is identified by two points at once, so the chance of two different
    /// journeys matching on both ends is small — and wide enough for a different parking
    /// space at either end.
    static let radiusMeters: Double = 250

    /// - Parameter trips: the history. Trips still waiting to be qualified are ignored:
    ///   their type is a default, not an answer, and learning from it would propagate a
    ///   guess into every trip that follows.
    static func match(
        start: (latitude: Double, longitude: Double)?,
        end: (latitude: Double, longitude: Double)?,
        excluding excludedID: UUID? = nil,
        in trips: [Trip],
        radiusMeters: Double = radiusMeters
    ) -> Pattern? {
        guard let start, let end else { return nil }

        let matches = trips
            .filter { $0.id != excludedID && $0.isReviewed && $0.endedAt != nil }
            .filter { trip in
                guard let tripStartLatitude = trip.startLatitude,
                      let tripStartLongitude = trip.startLongitude,
                      let tripEndLatitude = trip.endLatitude,
                      let tripEndLongitude = trip.endLongitude
                else { return false }
                // Direction matters: home → office and office → home are two journeys, and
                // for someone billing a client they are not always worth the same.
                return Geodesy.distance(
                    fromLatitude: start.latitude, longitude: start.longitude,
                    toLatitude: tripStartLatitude, longitude: tripStartLongitude
                ) <= radiusMeters
                    && Geodesy.distance(
                        fromLatitude: end.latitude, longitude: end.longitude,
                        toLatitude: tripEndLatitude, longitude: tripEndLongitude
                    ) <= radiusMeters
            }
            .sorted { $0.startedAt > $1.startedAt }

        // The most recent one decides. A count would be more stable and less correct: when
        // a route changes hands — a client becomes another client — the driver corrects one
        // trip and expects the next to follow, not to wait for a majority.
        guard let latest = matches.first else { return nil }
        return Pattern(
            tripType: latest.tripType,
            clientID: latest.clientID,
            projectID: latest.projectID,
            purpose: latest.purpose?.isEmpty == false ? latest.purpose : nil,
            occurrences: matches.count
        )
    }
}
