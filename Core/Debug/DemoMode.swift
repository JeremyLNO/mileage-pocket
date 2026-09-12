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
            context.insert(trip)
        }
        try? context.save()
        return true
    }
}
