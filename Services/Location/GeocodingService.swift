import CoreLocation
import Foundation

@MainActor
protocol Geocoding {
    func address(latitude: Double, longitude: Double) async -> String?
}

/// Reverse geocoding for the two ends of a trip, and nothing else.
///
/// `CLGeocoder` is rate limited per app, not per request: geocoding every fix would get the
/// whole app throttled within one drive. The recorder calls this exactly twice per trip.
@MainActor
final class GeocodingService: Geocoding {
    private let geocoder = CLGeocoder()

    /// Returns a short, human "where was this" string, or `nil` when the lookup fails.
    /// A missing address is a cosmetic gap in the trip list; it is never worth an error.
    func address(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return Self.format(placemark)
    }

    static func format(_ placemark: CLPlacemark) -> String? {
        // Street then town: enough for the user to recognise the trip in a list, short
        // enough to fit a report row.
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let town = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        let parts = [street.isEmpty ? nil : street, town].compactMap { $0 }
        if parts.isEmpty { return placemark.name }
        return parts.joined(separator: ", ")
    }
}
