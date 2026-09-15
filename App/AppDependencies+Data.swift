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

    /// How a trip is named on screen: towns when they differ, streets when both ends share
    /// one. Centralised so a list row, the detail screen and a report cannot disagree.
    nonisolated func endpointLabels(for trip: Trip) -> (start: String, end: String) {
        TripEndpointLabel.format(
            start: PlaceLabel(street: trip.startStreet, town: trip.startAddress),
            end: PlaceLabel(street: trip.endStreet, town: trip.endAddress),
            distanceMeters: trip.distanceMeters
        )
    }

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

    func projectName(for id: UUID) -> String? {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return projects.first { $0.id == id }?.name
    }

    /// Finds a project by name — within a client when one is given — or creates it. Matching
    /// mirrors `client(named:)`: case-insensitive, so the same project typed twice does not
    /// become two.
    func project(named name: String, clientID: UUID? = nil) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        if let existing = projects.first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
                && (clientID == nil || $0.clientID == clientID)
        }) {
            existing.lastUsedAt = .now
            if existing.clientID == nil { existing.clientID = clientID }
            return existing
        }
        let created = Project(name: trimmed, clientID: clientID)
        created.lastUsedAt = .now
        context.insert(created)
        return created
    }

    /// Deleting a client must not take its trips with it. A mileage log is a record: the
    /// drive happened, and losing it because a name was tidied up would be the one
    /// unrecoverable outcome. The trips are detached, and so are the client's projects.
    func deleteClient(_ client: Client) {
        let id = client.id
        for trip in (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.clientID == id }))) ?? [] {
            trip.clientID = nil
            trip.updatedAt = .now
        }
        for project in (try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.clientID == id }))) ?? [] {
            project.clientID = nil
        }
        context.delete(client)
        try? context.save()
        invalidate()
    }

    func deleteProject(_ project: Project) {
        let id = project.id
        for trip in (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.projectID == id }))) ?? [] {
            trip.projectID = nil
            trip.updatedAt = .now
        }
        context.delete(project)
        try? context.save()
        invalidate()
    }

    func tripCount(forClient id: UUID) -> Int {
        (try? context.fetchCount(FetchDescriptor<Trip>(predicate: #Predicate { $0.clientID == id }))) ?? 0
    }

    func tripCount(forProject id: UUID) -> Int {
        (try? context.fetchCount(FetchDescriptor<Trip>(predicate: #Predicate { $0.projectID == id }))) ?? 0
    }

    // MARK: - Vehicles

    /// A vehicle to edit, deliberately **not** inserted yet.
    ///
    /// Inserting it up front meant abandoning the editor — swiping the sheet away, which is
    /// how half of iOS is dismissed — left a nameless car in the list, and if it was the
    /// first one, a nameless car as the default. `saveVehicle` inserts it; nothing else has
    /// to remember to clean up.
    func makeVehicle() -> Vehicle {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        return Vehicle(name: "", vehicleType: .car, isDefault: vehicles.isEmpty)
    }

    func saveVehicle(_ vehicle: Vehicle) {
        if vehicle.modelContext == nil { context.insert(vehicle) }
        if vehicle.isDefault {
            // Exactly one default: two would make "which car was this?" unanswerable.
            let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
            for other in vehicles where other.id != vehicle.id {
                other.isDefault = false
            }
            settingsStore.settings.defaultVehicleID = vehicle.id
        }
        try? context.save()
        invalidate()
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
        return rule.isOfficial ? rule.summary : L.string("rate.custom")
    }

    func activeRuleSource() -> URL? { currentRule().sourceURL }

    func ruleAvailabilityMessage(for countryCode: String) -> String {
        if ruleEngine.officialPack(for: countryCode) != nil {
            let name = CountryCatalog.info(for: countryCode, locale: localization.locale)?.name ?? countryCode
            return L.format("onboarding.country.official", name)
        }
        return L.string("onboarding.country.custom")
    }

    // MARK: - Closing a period

    /// The closing record for a period, if it has one.
    func closedPeriod(for range: Range<Date>) -> ClosedPeriod? {
        let periods = (try? context.fetch(FetchDescriptor<ClosedPeriod>())) ?? []
        return periods.first { $0.covers(range) }
    }

    func closingStatus(for range: Range<Date>) -> PeriodClosing.Status {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        return PeriodClosing.status(trips: trips, range: range, closed: closedPeriod(for: range))
    }

    /// Files the period: what it was worth, at this moment, in one row.
    ///
    /// Refuses while trips in it are unqualified — a claim containing drives nobody has
    /// answered for is the thing the queue exists to prevent, and letting the closing screen
    /// walk past it would make both features pointless.
    @discardableResult
    func closePeriod(_ range: Range<Date>) -> Bool {
        let status = closingStatus(for: range)
        guard status.canClose else { return false }

        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? [])
            .filter { $0.endedAt != nil && range.contains($0.startedAt) }
        let amount = trips.compactMap(\.calculatedAmount).reduce(Decimal(0), +)
        context.insert(ClosedPeriod(
            startedAt: range.lowerBound,
            endedAt: range.upperBound,
            closedAt: .now,
            distanceMeters: trips.reduce(0) { $0 + $1.distanceMeters },
            amount: amount,
            currencyCode: trips.compactMap(\.currencyCode).first ?? settingsStore.settings.currencyCode,
            tripCount: trips.count
        ))
        try? context.save()
        invalidate()
        return true
    }

    /// Re-opens a filed period. The record is removed rather than kept as history: a period
    /// that is closed twice would otherwise leave two witnesses disagreeing about what was
    /// filed, and the one that matters is the last.
    func reopenPeriod(_ range: Range<Date>) {
        guard let period = closedPeriod(for: range) else { return }
        context.delete(period)
        try? context.save()
        invalidate()
    }

    // MARK: - Smart destinations

    func suggestedDestination(for trip: Trip) -> FrequentLocation? {
        guard let latitude = trip.endLatitude, let longitude = trip.endLongitude else { return nil }
        let known = (try? context.fetch(FetchDescriptor<FrequentLocation>())) ?? []
        return FrequentLocationMatcher.match(latitude: latitude, longitude: longitude, in: known)
    }

    /// What the last identical journey was, for a trip that has just ended.
    ///
    /// Reads the history rather than a learned table: a pattern that cannot drift from the
    /// trips it summarises is one nobody has to maintain.
    func pattern(for trip: Trip) -> TripPatternMatcher.Pattern? {
        guard let startLatitude = trip.startLatitude, let startLongitude = trip.startLongitude,
              let endLatitude = trip.endLatitude, let endLongitude = trip.endLongitude
        else { return nil }
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        return TripPatternMatcher.match(
            start: (startLatitude, startLongitude),
            end: (endLatitude, endLongitude),
            excluding: trip.id,
            in: trips
        )
    }

    /// Trips that have been recorded and never qualified, newest first.
    var tripsAwaitingReview: [Trip] {
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isReviewed && $0.endedAt != nil }
    }

    /// Qualifies a trip from the queue, in one gesture.
    ///
    /// Everything the summary sheet does on Save, minus the sheet: the type decides what the
    /// trip is worth, a tiered scale makes that ripple through the rest of the year, and the
    /// destination is learned from a trip whose classification is now a real answer.
    func reviewTrip(_ trip: Trip, as type: TripType) {
        trip.tripType = type
        trip.isReviewed = true
        trip.updatedAt = .now
        applyCalculation(to: trip)
        learnDestination(from: trip)
        try? context.save()
        recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
        refreshWidgetSnapshot()
        invalidate()
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
        // A manual entry is usually backdated, which is exactly what moves the rest of the
        // year onto different bands.
        recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
        refreshWidgetSnapshot()
        invalidate()
    }

    func delete(_ trip: Trip) {
        let date = trip.startedAt
        let country = trip.countryCode
        context.delete(trip)
        try? context.save()
        // Removing a trip moves every later one of that year down a band.
        recalculateCumulativeYear(containing: date, countryCode: country)
        refreshWidgetSnapshot()
        invalidate()
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
        recalculateCumulativeYear(containing: copy.startedAt, countryCode: copy.countryCode)
        invalidate()
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

    /// The archive behind "Export all my data", deliberately **not** behind the paywall.
    ///
    /// It used to hand back the very same CSV the paid export produces — in fact a superset,
    /// personal trips included — which made the paid export decorative. But a person must be
    /// able to leave with what they recorded, so the answer is not to remove it: it is to
    /// make it an *archive* rather than a *report*. JSON of the raw records, complete and
    /// machine-readable, with none of the formatting, totals or rule provenance that make the
    /// report worth paying for.
    func exportAllData() -> URL? {
        let trips = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let settings = settingsStore.settings

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Découpé en sous-expressions typées explicitement : en un seul littéral
        // `[String: Any]`, avec des dictionnaires hétérogènes imbriqués et trois
        // `map` à inférer, le vérificateur de types abandonne — « unable to
        // type-check this expression in reasonable time », archive en échec.
        // Xcode 27 y arrivait, Xcode 26.3 non : la fragilité est ici, pas dans le
        // compilateur, et rien n'avertit tant qu'on ne change pas de toolchain.
        let settingsPayload: [String: Any] = [
            "country": settings.countryCode,
            "currency": settings.currencyCode,
            "distanceUnit": settings.distanceUnitRaw,
        ]

        let vehiclesPayload: [[String: Any]] = vehicles.map { vehicle -> [String: Any] in
            [
                "id": vehicle.id.uuidString,
                "name": vehicle.name,
                "type": vehicle.vehicleTypeRaw,
                "registration": vehicle.registration ?? "",
            ]
        }

        let clientsPayload: [[String: Any]] = clients.map { client -> [String: Any] in
            ["id": client.id.uuidString, "name": client.name]
        }

        let tripsPayload: [[String: Any]] = trips.map { trip -> [String: Any] in
            [
                "id": trip.id.uuidString,
                "startedAt": formatter.string(from: trip.startedAt),
                "endedAt": trip.endedAt.map { formatter.string(from: $0) } ?? "",
                "distanceMeters": trip.distanceMeters,
                "type": trip.tripTypeRaw,
                "purpose": trip.purpose ?? "",
                "from": trip.startAddress ?? "",
                "fromStreet": trip.startStreet ?? "",
                "to": trip.endAddress ?? "",
                "toStreet": trip.endStreet ?? "",
                "country": trip.countryCode,
                "rate": trip.mileageRate.map { "\($0)" } ?? "",
                "amount": trip.calculatedAmount.map { "\($0)" } ?? "",
                "currency": trip.currencyCode ?? "",
                "unit": trip.mileageUnitRaw ?? "",
                "ruleVersion": trip.mileageRuleVersion ?? "",
                "vehicleId": trip.vehicleID?.uuidString ?? "",
                "manuallyEdited": trip.isManuallyEdited,
            ]
        }

        let payload: [String: Any] = [
            "exportedAt": formatter.string(from: .now),
            "app": "Mileage Pocket",
            "settings": settingsPayload,
            "vehicles": vehiclesPayload,
            "clients": clientsPayload,
            "trips": tripsPayload,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileagePocket-data.json")
        try? data.write(to: url, options: .atomic)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func reportProfile() -> ReportProfile {
        let settings = settingsStore.settings
        let rule = currentRule()
        let country = CountryCatalog.info(for: settings.countryCode, locale: localization.locale)
        return ReportProfile(
            userName: settings.userName ?? L.string("report.unnamed.driver"),
            companyName: settings.companyName,
            vehicleLabel: defaultVehicleName(),
            countryCode: settings.countryCode,
            countryName: country?.name ?? settings.countryCode,
            ruleDescription: rule.isOfficial ? rule.summary : L.string("rate.custom"),
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
        // The free period is deliberately NOT reset here: "delete my data" must not double
        // as "give me another three days".
        refreshWidgetSnapshot()
        invalidate()
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
            // Say how long is left rather than "no subscription": someone in their free days
            // should not have to discover the deadline by hitting it.
            if freePeriod.isActive() {
                return L.plural("settings.plan.freedays", freeDaysRemaining)
            }
            return L.string("settings.plan.free")
        case let .trial(productID, _):
            return L.string("settings.plan.trial") + " · " + planName(productID)
        case let .subscribed(productID, _):
            return planName(productID)
        case let .gracePeriod(productID, _):
            return planName(productID) + " · " + L.string("settings.plan.grace")
        }
    }

    private func planName(_ productID: String) -> String {
        ProductIDs.isAnnual(productID)
            ? L.string("paywall.plan.annual")
            : L.string("paywall.plan.monthly")
    }
}
