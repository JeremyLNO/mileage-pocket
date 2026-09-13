import CoreLocation
import Foundation

@MainActor
protocol Geocoding {
    func place(latitude: Double, longitude: Double) async -> PlaceLabel?
}

/// Reverse geocoding for the two ends of a trip, and nothing else.
///
/// `CLGeocoder` is rate limited per app, not per request: geocoding every fix would get the
/// whole app throttled within one drive. The recorder calls this exactly twice per trip.
@MainActor
final class GeocodingService: Geocoding {
    private let geocoder = CLGeocoder()

    /// Returns both levels of precision, or `nil` when the lookup fails. A missing address is
    /// a cosmetic gap in the trip list; it is never worth an error.
    func place(latitude: Double, longitude: Double) async -> PlaceLabel? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return Self.label(placemark)
    }

    /// Extracts both levels. Choosing between them is `TripEndpointLabel`'s job, not this
    /// one's: the right level depends on the trip, and it cannot be decided here where only
    /// one end is known.
    nonisolated static func label(_ placemark: CLPlacemark) -> PlaceLabel {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let town = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        return PlaceLabel(
            street: street.isEmpty ? placemark.name : street,
            town: (town?.isEmpty == false) ? town : nil
        )
    }
}
