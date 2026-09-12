import CoreLocation
import MapKit
import XCTest
@testable import MileagePocket

final class TripGroupingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 14, minute: 0))!
    }

    private func trip(_ offsetDays: Int, hour: Int = 12, minute: Int = 0) -> Trip {
        let day = calendar.date(byAdding: .day, value: offsetDays, to: calendar.startOfDay(for: now))!
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        let trip = Trip(startedAt: start)
        trip.endedAt = start.addingTimeInterval(600)
        return trip
    }

    func testJustAfterMidnightIsStillToday() {
        XCTAssertEqual(TripGrouping.section(for: trip(0, hour: 0, minute: 5).startedAt, now: now, calendar: calendar), .today)
    }

    func testLateLastNightIsYesterday() {
        XCTAssertEqual(TripGrouping.section(for: trip(-1, hour: 23, minute: 55).startedAt, now: now, calendar: calendar), .yesterday)
    }

    func testThreeDaysAgoIsThisWeek() {
        XCTAssertEqual(TripGrouping.section(for: trip(-3).startedAt, now: now, calendar: calendar), .thisWeek)
    }

    func testTwentyDaysAgoIsEarlier() {
        XCTAssertEqual(TripGrouping.section(for: trip(-20).startedAt, now: now, calendar: calendar), .earlier)
    }

    func testSevenDayBoundaryIsTestedOnTheBoundItself() {
        // Exactly seven days back, at the start of that day: the last moment that still
        // counts as "this week".
        let boundary = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(TripGrouping.section(for: boundary, now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(
            TripGrouping.section(for: boundary.addingTimeInterval(-1), now: now, calendar: calendar),
            .earlier
        )
    }

    func testEmptySectionsAreNotEmitted() {
        let groups = TripGrouping.group([trip(0), trip(-20)], now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.0), [.today, .earlier])
    }

    func testTripsAreSortedNewestFirstInsideASection() {
        let morning = trip(0, hour: 8)
        let evening = trip(0, hour: 19)
        let groups = TripGrouping.group([morning, evening], now: now, calendar: calendar)
        XCTAssertEqual(groups.first?.1.map(\.startedAt), [evening.startedAt, morning.startedAt])
    }

    /// A trip recorded in another time zone must not slide into the wrong day when the list
    /// is read at home: grouping follows the calendar in force now.
    func testGroupingFollowsTheCurrentCalendarNotTheRecordingZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let recordedAt = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9))!

        XCTAssertEqual(TripGrouping.section(for: recordedAt, now: now, calendar: calendar), .today)
    }
}

/// Trip endpoints are named by town. A full street address is the same information rendered
/// unreadable: it truncates in every list row and every report column.
final class GeocodingFormatTests: XCTestCase {
    private func placemark(
        subThoroughfare: String? = nil,
        thoroughfare: String? = nil,
        locality: String? = nil,
        subAdministrativeArea: String? = nil,
        administrativeArea: String? = nil,
        name: String? = nil
    ) -> CLPlacemark {
        // `CLPlacemark` cannot be built field by field, so the rule is asserted through
        // `MKPlacemark`, which can. Absent fields are left out of the dictionary entirely:
        // writing them as `nil as Any` puts an unusable value in and crashes the lookup.
        var address: [String: Any] = [:]
        if let subThoroughfare { address["SubThoroughfare"] = subThoroughfare }
        if let thoroughfare { address["Thoroughfare"] = thoroughfare }
        if let locality { address["City"] = locality }
        if let subAdministrativeArea { address["SubAdministrativeArea"] = subAdministrativeArea }
        if let administrativeArea { address["State"] = administrativeArea }
        if let name { address["Name"] = name }
        return MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), addressDictionary: address)
    }

    func testATownWinsOverAStreet() {
        let result = GeocodingService.format(placemark(subThoroughfare: "118", thoroughfare: "Voie Georges Pompidou", locality: "Paris"))
        XCTAssertEqual(result, "Paris")
    }

    func testAStreetIsUsedOnlyWhenThereIsNoTown() {
        let result = GeocodingService.format(placemark(subThoroughfare: "12", thoroughfare: "A6 Autoroute du Soleil"))
        XCTAssertEqual(result, "12 A6 Autoroute du Soleil")
    }

    func testFallsBackToTheNameWhenNothingElseIsKnown() {
        XCTAssertEqual(GeocodingService.format(placemark(name: "Somewhere")), "Somewhere")
    }
}
