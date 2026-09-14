import Foundation
import SwiftData

/// Launch-argument switches used for development and for producing App Store screenshots.
///
/// Compiled out of Release entirely — there is no path in a shipped build that reads these,
/// so a demo flag cannot be triggered on a user's device.
enum DemoMode {
    #if DEBUG
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--demo-data-only")
    }

    /// `--tab=trips` opens straight onto a tab, so a screenshot run needs no taps.
    static var initialTab: String? { value(forArgument: "--tab") }

    /// `--screen=paywall` presents one screen over the tabs.
    static var initialScreen: String? { value(forArgument: "--screen") }

    /// `--demo` unlocks premium so screenshots are not all paywalls; `--demo-data-only`
    /// seeds the same data but leaves the paywall real, which is what the review capture and
    /// the gating tests need.
    static var pretendsSubscribed: Bool { CommandLine.arguments.contains("--demo") }

    /// `--export-report` renders the current month's PDF and CSV into the app's Documents
    /// directory at launch, so they can be pulled off the simulator and looked at.
    static var exportsReport: Bool { CommandLine.arguments.contains("--export-report") }

    /// `--fake-store` draws the paywall from the bundled StoreKit configuration instead of a
    /// live query. It exists for one reason: App Store Connect requires a review screenshot
    /// of the paywall before the subscriptions can be submitted, and StoreKit answers
    /// nothing for an app the store has never seen.
    static var usesBundledStoreConfiguration: Bool { CommandLine.arguments.contains("--fake-store") }

    /// `--reset-onboarding` sends the app back to its first-run screens.
    static var resetsOnboarding: Bool {
        CommandLine.arguments.contains("--reset-onboarding") || onboardingStep != nil
    }

    /// `--reset-data` wipes the store and seeds it again. Tests that delete trips need it:
    /// the seed only runs on an empty store, so without this each run would permanently
    /// shrink the demo data until the suite ran out of rows to delete.
    static var resetsData: Bool { CommandLine.arguments.contains("--reset-data") }

    /// `--open-last-trip` pushes the most recent trip's detail as soon as the Trips tab
    /// appears. The trip screen — route on a map, figures beneath it — is the app's best
    /// single image, and it is two taps deep; capturing it from the host without automation
    /// needs this.
    static var opensLastTrip: Bool { CommandLine.arguments.contains("--open-last-trip") }

    /// `--reset-free-period` restarts the free days from now.
    static var resetsFreePeriod: Bool { CommandLine.arguments.contains("--reset-free-period") }

    /// `--onboarding-step=3` opens the flow directly on one screen, so each can be captured
    /// without chaining timed taps through the ones before it.
    static var onboardingStep: Int? { value(forArgument: "--onboarding-step").flatMap(Int.init) }
    #else
    static var isEnabled: Bool { false }
    static var initialTab: String? { nil }
    static var initialScreen: String? { nil }
    static var pretendsSubscribed: Bool { false }
    static var exportsReport: Bool { false }
    static var usesBundledStoreConfiguration: Bool { false }
    static var resetsOnboarding: Bool { false }
    static var onboardingStep: Int? { nil }
    static var resetsFreePeriod: Bool { false }
    static var opensLastTrip: Bool { false }
    static var resetsData: Bool { false }
    #endif

    private static func value(forArgument name: String) -> String? {
        for argument in CommandLine.arguments where argument.hasPrefix(name + "=") {
            return String(argument.dropFirst(name.count + 1))
        }
        return nil
    }

    /// Seeds a believable month: three named routes, a mix of business and personal, a
    /// vehicle, and two clients. Idempotent — a second launch does not double the data.
    /// - Returns: true when it actually inserted data, so the caller knows to run the
    ///   calculation pass over it.
    @discardableResult
    @MainActor
    static func seed(context: ModelContext, settings: UserSettings) -> Bool {
        guard isEnabled else { return false }
        if resetsData {
            for trip in (try? context.fetch(FetchDescriptor<Trip>())) ?? [] { context.delete(trip) }
            for vehicle in (try? context.fetch(FetchDescriptor<Vehicle>())) ?? [] { context.delete(vehicle) }
            for client in (try? context.fetch(FetchDescriptor<Client>())) ?? [] { context.delete(client) }
            try? context.save()
        }
        let existing = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        guard existing.isEmpty else { return false }

        settings.hasCompletedOnboarding = true
        settings.userName = "Jane Doe"
        settings.companyName = "Doe Consulting"
        settings.countryCode = "FR"
        settings.currencyCode = "EUR"
        settings.distanceUnit = .kilometers

        let vehicle = Vehicle(name: "Tesla Model 3", vehicleType: .electricCar, isDefault: true)
        vehicle.registration = "AB-123-CD"
        vehicle.fiscalHorsepower = 5
        context.insert(vehicle)
        settings.defaultVehicleID = vehicle.id

        let acme = Client(name: "Acme Industries")
        let northwind = Client(name: "Northwind")
        context.insert(acme)
        context.insert(northwind)

        /// Real coordinates, so the demo trips carry a route the map can draw. Without them
        /// the trip screen showed everything *except* the thing it is built around, and the
        /// map card was reachable by no screenshot and no demo.
        let places: [String: (Double, Double)] = [
            "Paris": (48.8656, 2.3212),
            "Versailles": (48.8014, 2.1301),
            "Orly": (48.7233, 2.3794),
            "Boulogne": (48.8352, 2.2409),
            "Saint-Denis": (48.9362, 2.3574),
            "Fontainebleau": (48.4045, 2.7016),
            "Meudon": (48.8140, 2.2350),
            "Rueil-Malmaison": (48.8760, 2.1800),
        ]

        let routes: [(String, String, Double, String, TripType, UUID?)] = [
            ("Paris", "Versailles", 24_300, "Client meeting", .business, acme.id),
            ("Paris", "Orly", 18_700, "Airport run", .business, northwind.id),
            ("Paris", "Boulogne", 9_400, "Site visit", .business, acme.id),
            ("Versailles", "Paris", 24_100, "Client meeting", .business, acme.id),
            ("Paris", "Saint-Denis", 12_600, "Delivery", .business, northwind.id),
            ("Paris", "Fontainebleau", 64_800, "Site visit", .business, acme.id),
            ("Paris", "Meudon", 11_200, "", .personal, nil),
            ("Paris", "Rueil-Malmaison", 16_900, "Client meeting", .business, northwind.id),
        ]

        let calendar = Calendar.current
        for (index, route) in routes.enumerated() {
            let start = calendar.date(byAdding: .day, value: -(index * 2 + 1), to: .now) ?? .now
            let trip = Trip(startedAt: calendar.date(bySettingHour: 8 + index % 8, minute: 15, second: 0, of: start) ?? start)
            trip.endedAt = trip.startedAt.addingTimeInterval(1_200 + Double(index) * 240)
            trip.rawDistanceMeters = route.2
            trip.startAddress = route.0
            trip.endAddress = route.1
            trip.purpose = route.3.isEmpty ? nil : route.3
            trip.tripType = route.4
            trip.clientID = route.5
            trip.vehicleID = vehicle.id
            trip.countryCode = "FR"
            // The two most recent drives arrive unqualified, the way real ones do: the demo
            // has to show the queue that the app now opens with, not a library that has
            // never had a trip waiting in it.
            trip.isReviewed = index >= 2
            if let from = places[route.0], let to = places[route.1] {
                trip.startLatitude = from.0
                trip.startLongitude = from.1
                trip.endLatitude = to.0
                trip.endLongitude = to.1
                trip.encodedRoute = RouteCompactor.encode(
                    demoRoute(from: from, to: to, startedAt: trip.startedAt, seed: index)
                )
            }
            context.insert(trip)
        }
        try? context.save()
        return true
    }

    /// A plausible drive between two points: a shallow arc rather than a straight line, so
    /// the map reads as a road and not as a ruler.
    private static func demoRoute(
        from: (Double, Double),
        to: (Double, Double),
        startedAt: Date,
        seed: Int
    ) -> [LocationSample] {
        let steps = 64
        // Perpendicular bow, alternating side per trip so eight routes do not all curve the
        // same way.
        let bow = (seed.isMultiple(of: 2) ? 1.0 : -1.0) * 0.12
        let dLat = to.0 - from.0
        let dLon = to.1 - from.1

        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let arc = 4 * t * (1 - t)          // 0 at both ends, 1 in the middle
            return LocationSample(
                latitude: from.0 + dLat * t - dLon * bow * arc,
                longitude: from.1 + dLon * t + dLat * bow * arc,
                horizontalAccuracy: 5,
                altitude: 40,
                speed: 22,
                timestamp: startedAt.addingTimeInterval(Double(step) * 18)
            )
        }
    }
}
