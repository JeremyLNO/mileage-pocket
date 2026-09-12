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

    /// The town, not the street.
    ///
    /// "Paris → Versailles" is what a trip is called; "118 Voie Georges Pompidou, Paris →
    /// 4 Avenue de…" is the same information rendered unreadable, and it truncates in every
    /// list row and every report column. The exact position is on the map where it belongs.
    /// A street name is used only when there is no town to name — a motorway, open country.
    nonisolated static func format(_ placemark: CLPlacemark) -> String? {
        if let town = placemark.locality ?? placemark.subAdministrativeArea {
            return town
        }
        if let area = placemark.administrativeArea, !area.isEmpty {
            return area
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        return street.isEmpty ? placemark.name : street
    }
}
