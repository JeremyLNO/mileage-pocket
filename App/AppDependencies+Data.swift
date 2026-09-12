import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// Store queries, exports and the small object factories the views need. Split out of
/// `AppDependencies` so the lifecycle file stays about the trip lifecycle.
extension AppDependencies {
    // MARK: - Lookups

    func vehicle(for id: UUID?) -> Vehicle? {
        guard let id else { return defaultVehicle() }
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        return vehicles.first { $0.id == id } ?? defaultVehicle()
    }

    func defaultVehicle() -> Vehicle? {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let id = settingsStore.settings.defaultVehicleID, let match = vehicles.first(where: { $0.id == id }) {
            return match
        }
        return vehicles.first(where: \.isDefault) ?? vehicles.first
    }

    func defaultVehicleName() -> String? { defaultVehicle()?.name }

    func vehicleName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return vehicle(for: id)?.name
    }

    func vehicleNames() -> [UUID: String] {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        return Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0.name) })
    }

    func clientName(for id: UUID) -> String? {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return clients.first { $0.id == id }?.name
    }

    /// Finds a client by name or creates one. Matching is case-insensitive so "Acme" typed
    /// twice with different capitals does not become two clients.
    func client(named name: String) -> Client {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        if let existing = clients.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            existing.lastUsedAt = .now
            return existing
        }
        let created = Client(name: trimmed)
        created.lastUsedAt = .now
        context.insert(created)
        return created
    }

    // MARK: - Vehicles

    func makeVehicle() -> Vehicle {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let vehicle = Vehicle(name: "", vehicleType: .car, isDefault: vehicles.isEmpty)
        context.insert(vehicle)
        return vehicle
    }

    func saveVehicle(_ vehicle: Vehicle) {
        if vehicle.isDefault {
            // Exactly one default: two would make "which car was this?" unanswerable.
            let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
            for other in vehicles where other.id != vehicle.id {
                other.isDefault = false
            }
            settingsStore.settings.defaultVehicleID = vehicle.id
        }
        try? context.save()
        recorderRevision += 1
    }

    func createOnboardingVehicle(
        name: String,
        type: VehicleType,
        registration: String,
        fiscalHorsepower: Int?,
        engineCapacity: Int?
    ) {
        let vehicle = Vehicle(name: name, vehicleType: type, isDefault: true)
        vehicle.registration = registration.isEmpty ? nil : registration
        vehicle.fiscalHorsepower = fiscalHorsepower
        vehicle.engineCapacity = engineCapacity
        context.insert(vehicle)
        settingsStore.settings.defaultVehicleID = vehicle.id
        settingsStore.save()
    }

    // MARK: - Rules

    func hasOfficialRule(countryCode: String? = nil) -> Bool {
        ruleEngine.hasOfficialRule(for: countryCode ?? settingsStore.settings.countryCode)
    }

    /// Which power figure, if any, this country's scale bands by. `nil` means the vehicle
    /// form should not ask for one at all.
    func requiredPowerUnit(countryCode: String? = nil) -> PowerUnit? {
        let code = countryCode ?? settingsStore.settings.countryCode
        guard let pack = ruleEngine.officialPack(for: code) else { return nil }
        guard let scheme = pack.schemes.first(where: { ($0.powerBands?.isEmpty == false) }) else { return nil }
        return scheme.powerUnit
    }

    func activeRuleDescription() -> String {
        let rule = currentRule()
        return rule.isOfficial ? rule.summary : String(localized: "rate.custom")
    }

    func activeRuleSource() -> URL? { currentRule().sourceURL }

    func ruleAvailabilityMessage(for countryCode: String) -> String {
        if let pack = ruleEngine.officialPack(for: countryCode) {
            return String(format: String(localized: "onboarding.country.official"), pack.source)
        }
        return String(localized: "onboarding.country.custom")
    }

    // MARK: - Smart destinations

    func suggestedDestination(for trip: Trip) -> FrequentLocation? {
        guard let latitude = trip.endLatitude, let longitude = trip.endLongitude else { return nil }
        let known = (try? context.fetch(FetchDescriptor<FrequentLocation>())) ?? []
        return FrequentLocationMatcher.match(latitude: latitude, longitude: longitude, in: known)
    }

    func learnDestination(from trip: Trip) {
        guard let latitude = trip.endLatitude, let longitude = trip.endLongitude else { return }
        let known = (try? context.fetch(FetchDescriptor<FrequentLocation>())) ?? []

        if let existing = FrequentLocationMatcher.match(latitude: latitude, longitude: longitude, in: known) {
            existing.visitCount += 1
            existing.lastVisitedAt = .now
            if existing.clientID == nil { existing.clientID = trip.clientID }
            if existing.purpose == nil { existing.purpose = trip.purpose }
            return
        }

        let location = FrequentLocation(latitude: latitude, longitude: longitude, address: trip.endAddress)
        location.clientID = trip.clientID
        location.purpose = trip.purpose
        location.label = trip.endAddress
        context.insert(location)
    }

    // MARK: - Trips

    func createManualTrip(
        date: Date,
        from: String,
        to: String,
        distanceMeters: Double,
        tripType: TripType,
        purpose: String,
        clientName: String,
        vehicleID: UUID?
    ) {
        let trip = Trip(startedAt: date)
        trip.endedAt = date
        trip.rawDistanceMeters = distanceMeters
        trip.startAddress = from.isEmpty ? nil : from
        trip.endAddress = to.isEmpty ? nil : to
        trip.tripType = tripType
        trip.purpose = purpose.isEmpty ? nil : purpose
        trip.vehicleID = vehicleID ?? defaultVehicle()?.id
        trip.isManualEntry = true
        if !clientName.isEmpty { trip.clientID = client(named: clientName).id }
        context.insert(trip)
        applyCalculation(to: trip)
        try? context.save()
        refreshWidgetSnapshot()
        recorderRevision += 1
    }

    func duplicate(_ trip: Trip) {
        let copy = Trip(startedAt: .now)
        copy.endedAt = Date.now.addingTimeInterval(trip.duration)
        copy.rawDistanceMeters = trip.rawDistanceMeters
        copy.correctedDistanceMeters = trip.correctedDistanceMeters
        copy.startAddress = trip.startAddress
        copy.endAddress = trip.endAddress
        copy.startLatitude = trip.startLatitude
        copy.startLongitude = trip.startLongitude
        copy.endLatitude = trip.endLatitude
        copy.endLongitude = trip.endLongitude
        copy.tripType = trip.tripType
        copy.purpose = trip.purpose
        copy.clientID = trip.clientID
        copy.projectID = trip.projectID
        copy.vehicleID = trip.vehicleID
        copy.isManualEntry = true
        // The route is not copied: a duplicate is a new drive, and showing yesterday's trace
        // on it would be a claim the app cannot support.
        context.insert(copy)
        applyCalculation(to: copy)
        try? context.save()
        recorderRevision += 1
    }

    // MARK: - Exports

    func export(_ data: ReportData, format: ExportFormat) -> URL? {
        let profile = reportProfile()
        let directory = FileManager.default.temporaryDirectory
        switch format {
        case .csv:
            let url = directory.appendingPathComponent(CSVExporter.fileName(for: data, locale: profile.locale))
            try? CSVExporter.write(CSVExporter.csv(data, profile: profile), to: url)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .pdf:
            let name = CSVExporter.fileName(for: data, locale: profile.locale).replacingOccurrences(of: ".csv", with: ".pdf")
            let url = directory.appendingPathComponent(name)
            return try? PDFReportRenderer().render(data, profile: profile, to: url)
        }
    }

    /// The plain data dump in Settings, deliberately **not** behind the paywall: a person's
    /// own record has to remain retrievable whether or not they are paying.
    func exportAllData() -> URL? {
        let trips = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let data = ReportBuilder.build(
            trips: trips,
            period: .custom(start: trips.first?.startedAt ?? .now, end: trips.last?.startedAt ?? .now),
            includePersonal: true,
            vehicleNames: vehicleNames(),
            fallbackCurrency: settingsStore.settings.currencyCode
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileagePocket-AllData.csv")
        try? CSVExporter.write(CSVExporter.csv(data, profile: reportProfile()), to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func reportProfile() -> ReportProfile {
        let settings = settingsStore.settings
        let rule = currentRule()
        let country = CountryCatalog.info(for: settings.countryCode, locale: localization.locale)
        return ReportProfile(
            userName: settings.userName ?? String(localized: "report.unnamed.driver"),
            companyName: settings.companyName,
            vehicleLabel: defaultVehicleName(),
            countryCode: settings.countryCode,
            countryName: country?.name ?? settings.countryCode,
            ruleDescription: rule.isOfficial ? rule.summary : String(localized: "rate.custom"),
            ruleVersion: rule.version,
            ruleSourceURL: rule.sourceURL,
            isOfficialRate: rule.isOfficial,
            unit: settings.distanceUnit,
            locale: localization.locale
        )
    }

    // MARK: - Data management

    func deleteAllData() {
        for trip in (try? context.fetch(FetchDescriptor<Trip>())) ?? [] { context.delete(trip) }
        for point in (try? context.fetch(FetchDescriptor<LocationPoint>())) ?? [] { context.delete(point) }
        for vehicle in (try? context.fetch(FetchDescriptor<Vehicle>())) ?? [] { context.delete(vehicle) }
        for client in (try? context.fetch(FetchDescriptor<Client>())) ?? [] { context.delete(client) }
        for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] { context.delete(project) }
        for place in (try? context.fetch(FetchDescriptor<FrequentLocation>())) ?? [] { context.delete(place) }
        for state in (try? context.fetch(FetchDescriptor<ActiveTripState>())) ?? [] { context.delete(state) }
        try? context.save()
        refreshWidgetSnapshot()
        recorderRevision += 1
    }

    // MARK: - Widget

    func refreshWidgetSnapshot() {
        let settings = settingsStore.settings
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let data = ReportBuilder.build(trips: trips, period: .current(), fallbackCurrency: settings.currencyCode)
        WidgetSnapshotStore.write(
            WidgetSnapshot(
                monthLabel: Date.now.formatted(.dateTime.month(.wide).locale(localization.locale)),
                distanceMeters: data.totalDistanceMeters,
                unitRaw: settings.distanceUnitRaw,
                formattedAmount: data.totalAmount > 0
                    ? Fmt.money(data.totalAmount, currencyCode: data.currencyCode, locale: localization.locale)
                    : nil,
                isTripInProgress: isRecording,
                updatedAt: .now
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    func subscriptionDescription() -> String {
        switch subscriptions.entitlement {
        case .none:
            return String(localized: "settings.plan.free")
        case let .trial(productID, _):
            return String(localized: "settings.plan.trial") + " · " + planName(productID)
        case let .subscribed(productID, _):
            return planName(productID)
        case let .gracePeriod(productID, _):
            return planName(productID) + " · " + String(localized: "settings.plan.grace")
        }
    }

    private func planName(_ productID: String) -> String {
        ProductIDs.isAnnual(productID)
            ? String(localized: "paywall.plan.annual")
            : String(localized: "paywall.plan.monthly")
    }
}
