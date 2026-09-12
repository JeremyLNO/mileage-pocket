import Foundation
import Observation
import SwiftData
import SwiftUI
import CoreLocation

/// The app's composition root.
///
/// Services are built once here and handed down through the SwiftUI environment. Views never
/// reach for a shared instance of anything, which is what lets the calculation engine, the
/// recorder and the store all be swapped for fakes in tests.
@Observable
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let context: ModelContext
    let settingsStore: SettingsStore
    let localization: LocalizationService
    let subscriptions: SubscriptionService
    let ruleEngine: CountryRuleEngine
    let recorder: any TripRecording
    let notifications: NotificationService
    let liveActivity: TripActivityController
    let rulePackUpdater: RulePackUpdater?

    /// Bumped whenever a trip starts, stops or is saved. Views observe it to recompute their
    /// figures — a value that changes is cheaper to watch than the whole store.
    private(set) var recorderRevision = 0
    private(set) var activeRoute: [CLLocationCoordinate2D] = []
    /// Set the moment a trip stops, cleared when the summary sheet is done with it.
    var finishedTrip: Trip?

    init(
        container: ModelContainer,
        recorderFactory: ((ModelContext) -> any TripRecording)? = nil
    ) {
        self.container = container
        let context = ModelContext(container)
        self.context = context

        let settingsStore = SettingsStore(context: context)
        self.settingsStore = settingsStore
        self.localization = LocalizationService(settings: settingsStore.settings)
        self.subscriptions = SubscriptionService()

        let store = RulePackStore()
        self.ruleEngine = CountryRuleEngine(store: store)
        self.rulePackUpdater = AppLinks.rulePackEndpoint.map { RulePackUpdater(endpoint: $0, store: store) }

        self.notifications = NotificationService()
        self.liveActivity = TripActivityController()
        self.recorder = recorderFactory?(context) ?? TripRecorder(context: context)
    }

    func bootstrap() {
        subscriptions.start()
        try? recorder.resumeIfNeeded()
        syncRecorderState()
        // Fire-and-forget: a rule pack refresh must never hold up a launch, and the endpoint
        // is not deployed yet, so failing is the expected path in V1.
        Task.detached(priority: .background) { [rulePackUpdater] in
            await rulePackUpdater?.refresh()
        }
    }

    // MARK: - Trip lifecycle

    var isRecording: Bool {
        if case .idle = recorder.state { return false }
        return true
    }

    var isTripPaused: Bool {
        if case .paused = recorder.state { return true }
        return false
    }

    var activeDistanceMeters: Double {
        switch recorder.state {
        case .idle: return 0
        case let .recording(_, distance, _): return distance
        case .paused: return recorder.currentDistanceMeters
        }
    }

    func activeDuration(now: Date) -> TimeInterval {
        guard let startedAt = recorder.startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    var activeVehicleName: String? {
        defaultVehicleName()
    }

    func startTrip() {
        let vehicleID = settingsStore.settings.defaultVehicleID ?? defaultVehicle()?.id
        do {
            try recorder.start(vehicleID: vehicleID)
            liveActivity.start(
                vehicleName: activeVehicleName ?? String(localized: "home.no.vehicle"),
                unit: settingsStore.settings.distanceUnit,
                startedAt: recorder.startedAt ?? .now
            )
            notifications.scheduleTripStillRunningReminder()
            syncRecorderState()
        } catch {
            // Starting can only fail for want of location permission; the view already shows
            // the permission state, so there is nothing useful to raise here.
            syncRecorderState()
        }
    }

    func stopTrip() {
        let startedAt = recorder.startedAt ?? .now
        let distance = activeDistanceMeters
        let unit = settingsStore.settings.distanceUnit

        Task {
            defer {
                liveActivity.end(distanceMeters: distance, startedAt: startedAt, unit: unit)
                notifications.cancelTripReminders()
                syncRecorderState()
            }
            guard let trip = try? await recorder.stop() else { return }
            applyCalculation(to: trip)
            try? context.save()
            finishedTrip = trip
        }
    }

    /// Called when the summary sheet's Save is pressed: the classification is already on the
    /// trip, so this is where the amount is fixed and the learned places are updated.
    func finishTrip(_ trip: Trip) {
        applyCalculation(to: trip)
        learnDestination(from: trip)
        trip.updatedAt = .now
        try? context.save()
        finishedTrip = nil
        refreshWidgetSnapshot()
        recorderRevision += 1
    }

    func clearFinishedTrip() {
        finishedTrip = nil
        refreshWidgetSnapshot()
        recorderRevision += 1
    }

    func syncRecorderState() {
        activeRoute = recorder.routeCoordinates
        recorderRevision += 1
    }

    // MARK: - Calculation

    /// Freezes the applicable rule onto the trip. A personal trip is worth nothing and is
    /// recorded as such rather than left with a stale figure from a previous classification.
    func applyCalculation(to trip: Trip) {
        let settings = settingsStore.settings
        trip.countryCode = settings.countryCode

        guard trip.tripType == .business else {
            trip.calculatedAmount = 0
            trip.mileageRate = 0
            trip.currencyCode = settings.currencyCode
            return
        }

        let rule = currentRule(on: trip.startedAt)
        let allTrips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let yearly = ReportBuilder.yearlyDistanceMeters(before: trip, in: allTrips)

        let calculation = rule.calculate(
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle(for: trip.vehicleID),
            date: trip.startedAt,
            yearlyDistanceMeters: yearly
        )

        trip.mileageRate = calculation.rate
        trip.calculatedAmount = calculation.amount
        trip.currencyCode = calculation.currencyCode
        trip.mileageRuleVersion = calculation.ruleVersion
        trip.isOfficialRate = calculation.isOfficial
        trip.rateMode = settings.rateMode
    }

    /// Re-runs the calculation under the rule **already recorded on the trip**, which is what
    /// a manual distance correction needs: the distance changed, the applicable scale did not.
    func recalculateWithFrozenRule(_ trip: Trip) {
        guard trip.tripType == .business, let rate = trip.mileageRate else {
            try? context.save()
            return
        }
        let unit = settingsStore.settings.distanceUnit
        let distance = Decimal(unit.value(fromMeters: trip.distanceMeters))
        trip.calculatedAmount = MileageRounding.money(distance * rate)
        trip.updatedAt = .now
        try? context.save()
        recorderRevision += 1
    }

    /// The explicit "recalculate with today's rules" action, and the only path allowed to
    /// move an old trip onto a new scale.
    func recalculate(_ trip: Trip) {
        applyCalculation(to: trip)
        trip.updatedAt = .now
        try? context.save()
        recorderRevision += 1
    }

    func currentRule(on date: Date = .now) -> MileageRule {
        let settings = settingsStore.settings
        let customRate = settings.rateMode == .employer ? settings.employerRate : settings.customRate
        return ruleEngine.rule(
            countryCode: settings.countryCode,
            mode: settings.rateMode,
            customRate: customRate,
            customCurrency: settings.currencyCode,
            unit: settings.distanceUnit,
            date: date
        )
    }

    // MARK: - Permissions

    func requestLocationPermission() {
        recorder.requestPermission()
    }

    func requestNotificationPermission() async {
        let granted = await notifications.requestAuthorization()
        settingsStore.settings.notificationsEnabled = granted
        if granted { notifications.scheduleMonthlyReportReminder() }
        settingsStore.save()
    }

    func completeOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.save()
        recorderRevision += 1
    }

    var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
