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

    /// When the free period started, read once at launch from the keychain.
    private(set) var freePeriod: FreeAccessPeriod = FreeAccessPeriod(startedAt: .now)

    /// Whether `feature` is available right now.
    ///
    /// Three sources decide it: an active subscription, the free period every install gets,
    /// and the feature itself — exporting is never free. Views ask this and nothing else, so
    /// the rule lives in one place instead of being re-derived per screen.
    func canAccess(_ feature: PremiumFeature, now: Date = .now) -> Bool {
        if DemoMode.pretendsSubscribed { return true }
        return AccessPolicy.allows(
            feature,
            entitlement: subscriptions.entitlement,
            freePeriodActive: freePeriod.isActive(now: now)
        )
    }

    var freeDaysRemaining: Int { freePeriod.daysRemaining() }

    /// True once the free period is over and nothing has been purchased — the moment the
    /// paywall starts standing in the way.
    var needsSubscription: Bool {
        !subscriptions.entitlement.isActive && !freePeriod.isActive()
    }

    /// Tells the views something in the store changed under them. Named rather than letting
    /// callers poke the counter, so the reason for a redraw stays greppable.
    func invalidate() { recorderRevision += 1 }
    private(set) var activeRoute: [CLLocationCoordinate2D] = []
    /// Mirrors of the recorder's live state. `TripRecorder` is a service and is not
    /// `@Observable`: a SwiftUI body that reads it directly observes nothing and never
    /// redraws — which is exactly what kept the trip screen from opening after START.
    private(set) var isRecording = false
    private(set) var isTripPaused = false
    private(set) var activeDistanceMeters: Double = 0
    private(set) var activeStartedAt: Date?
    /// Set when a trip could not start because location is off or refused. The view shows it;
    /// before, the app opened its driving screen and recorded nothing, saying nothing.
    var locationRefused = false
    /// Set the moment a trip stops, cleared when the summary sheet is done with it.
    var finishedTrip: Trip?
    /// Set when `stop()` could not write the trip. The recorder has put itself back to
    /// recording, so the drive continues; this is what tells the driver to try again.
    var stopFailed = false

    /// How the store opened. Anything but `.healthy` is surfaced to the user: an app that
    /// quietly records into an in-memory store looks perfectly normal right up until the
    /// launch where the week's drives are gone.
    let storeHealth: StoreHealth

    /// Set once at launch when `storeHealth` is not `.healthy`, cleared when the user has
    /// read it. Held here rather than in the view so dismissing it survives a redraw.
    var storeWarningPending = false

    init(
        container: ModelContainer,
        storeHealth: StoreHealth = .healthy,
        recorderFactory: ((ModelContext) -> any TripRecording)? = nil
    ) {
        self.container = container
        self.storeHealth = storeHealth
        self.storeWarningPending = storeHealth != .healthy
        // The container's own main context, never a second one.
        //
        // `.modelContainer(_:)` hands views `container.mainContext`, which is what every
        // `@Query` observes. A private `ModelContext(container)` alongside it means writes
        // land in a context no list is watching: deleting a trip persisted, but the row
        // stayed on screen until the next launch.
        let context = container.mainContext
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
        self.recorder = recorderFactory?(context) ?? TripRecorder(
            context: context,
            provider: CoreLocationProvider(),
            geocoder: GeocodingService()
        )
    }

    /// Guards against a second pass. `bootstrap()` is called from the app's `init` — so that
    /// a launch *into the background*, woken by a significant location change after iOS
    /// terminated the app mid-drive, resumes the trip even though no view is ever built —
    /// and again from the root view's `task`, which is what covers every ordinary launch.
    private var didBootstrap = false

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        // Read (and, on a first launch, written) before anything can ask about access.
        if DemoMode.resetsFreePeriod {
            InstallDateStore.clear()
        }
        freePeriod = FreeAccessPeriod(startedAt: InstallDateStore.firstLaunchDate())
        recorder.onUpdate = { [weak self] in self?.syncRecorderState() }
        // The first trip of a user's life starts before the prompt is answered; when the
        // answer arrives, background delivery is enabled and the screen stops lying.
        recorder.onAuthorizationChange = { [weak self] status in
            guard let self else { return }
            locationRefused = (status == .denied || status == .restricted) && isRecording
            syncRecorderState()
        }
        if DemoMode.seed(context: context, settings: settingsStore.settings) {
            // Seeded trips go through the same calculation path as recorded ones — a demo
            // that skipped it would show a screen no real user ever sees.
            for trip in (try? context.fetch(FetchDescriptor<Trip>())) ?? [] {
                applyCalculation(to: trip)
            }
            try? context.save()
        }
        applyDebugOnboardingState()
        subscriptions.start()
        adoptTripInProgress()
        syncRecorderState()
        exportDemoReportIfRequested()
        // Fire-and-forget: a rule pack refresh must never hold up a launch, and the endpoint
        // is not deployed yet, so failing is the expected path in V1.
        Task.detached(priority: .background) { [rulePackUpdater] in
            await rulePackUpdater?.refresh()
        }
    }

    /// Picks up whatever the last run left behind.
    ///
    /// A trip too old to still be the one being driven is closed at its last fix rather than
    /// resumed — it is a real drive and must be kept — and the Live Activity from the
    /// previous run is re-adopted or cleared, so the lock screen never shows a trip that is
    /// no longer running.
    private func adoptTripInProgress() {
        let outcome = (try? recorder.resumeIfNeeded()) ?? ResumeOutcome.none
        if case .recovered(let trip) = outcome {
            applyCalculation(to: trip)
            try? context.save()
            recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
            Task { [recorder] in await recorder.attachPlaces(to: trip) }
        }
        liveActivity.adopt(isRecording: outcome == .resumed)
    }

    /// Onboarding state is set from the launch flags on **every** launch, not only when the
    /// demo data is first seeded. Deciding it inside the seeding branch made it stick from a
    /// previous run: a test that had reset onboarding left every later `--demo` launch
    /// sitting on the welcome screen, and five UI tests failed looking for a control that was
    /// one screen away.
    private func applyDebugOnboardingState() {
        guard DemoMode.isEnabled || DemoMode.resetsOnboarding else { return }
        settingsStore.settings.hasCompletedOnboarding = !DemoMode.resetsOnboarding
        settingsStore.save()
    }

    /// Development affordance: writes the month's report where `simctl get_app_container` can
    /// reach it. Compiled out of Release with the rest of `DemoMode`.
    private func exportDemoReportIfRequested() {
        guard DemoMode.exportsReport else { return }
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let data = ReportBuilder.build(
            trips: trips,
            period: .current(),
            vehicleNames: vehicleNames(),
            fallbackCurrency: settingsStore.settings.currencyCode
        )
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        _ = try? PDFReportRenderer().render(data, profile: reportProfile(), to: documents.appendingPathComponent("report.pdf"))
        try? CSVExporter.write(CSVExporter.csv(data, profile: reportProfile()), to: documents.appendingPathComponent("report.csv"))
    }

    // MARK: - Trip lifecycle

    func activeDuration(now: Date) -> TimeInterval {
        guard let startedAt = activeStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    var activeVehicleName: String? {
        defaultVehicleName()
    }

    func startTrip() {
        // Asked here, not only in onboarding: someone who skipped that step still presses
        // START, and a trip that records nothing because nobody ever asked is the worst
        // possible outcome — it looks like it is working.
        if recorder.authorizationStatus == .notDetermined {
            recorder.requestPermission()
        }
        let vehicleID = settingsStore.settings.defaultVehicleID ?? defaultVehicle()?.id
        do {
            try recorder.start(vehicleID: vehicleID)
            liveActivity.start(
                vehicleName: activeVehicleName ?? L.string("home.no.vehicle"),
                unit: settingsStore.settings.distanceUnit,
                startedAt: recorder.startedAt ?? .now
            )
            if settingsStore.settings.notificationsEnabled, settingsStore.settings.tripReminderEnabled {
                notifications.scheduleTripStillRunningReminder()
            }
            syncRecorderState()
        } catch RecorderError.locationUnavailable {
            // Recording without location produced a running timer over a 0 m trip and said
            // nothing at all. Refuse visibly instead.
            locationRefused = true
            syncRecorderState()
        } catch {
            syncRecorderState()
        }
    }

    func stopTrip() {
        let startedAt = recorder.startedAt ?? .now
        let distance = activeDistanceMeters
        let unit = settingsStore.settings.distanceUnit

        do {
            let trip = try recorder.stop()
            applyCalculation(to: trip)
            try? context.save()
            finishedTrip = trip
            // The addresses are fetched after the trip is on screen. Reverse-geocoding is two
            // network calls with no deadline of their own; making STOP wait for them meant a
            // driver pressing Stop and watching a frozen screen for several seconds.
            Task { [recorder] in
                await recorder.attachPlaces(to: trip)
                invalidate()
            }
        } catch {
            // The recorder rolled back and is recording again, so the drive is not lost
            // — but saying nothing would leave the driver pressing a STOP that appears
            // to do nothing at all. The lock screen and the reminders stay up precisely
            // because the trip is still running.
            stopFailed = true
            syncRecorderState()
            return
        }
        liveActivity.end(distanceMeters: distance, startedAt: startedAt, unit: unit)
        notifications.cancelTripReminders()
        syncRecorderState()
    }

    /// Applies an edit made on the trip detail screen.
    ///
    /// The classification and the vehicle both change what the trip is worth, and a tiered
    /// scale makes that change ripple through the rest of the year — a trip reclassified as
    /// personal gives its kilometres back to the allowance, and every later trip of that year
    /// is worth more. Repricing only this one row would leave the year internally
    /// inconsistent, which is exactly the bug the cumulative recalculation exists for.
    func repriceEditedTrip(_ trip: Trip) {
        applyCalculation(to: trip)
        trip.updatedAt = .now
        try? context.save()
        recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
        invalidate()
    }

    /// Called when the summary sheet's Save is pressed: the classification is already on the
    /// trip, so this is where the amount is fixed and the learned places are updated.
    func finishTrip(_ trip: Trip) {
        applyCalculation(to: trip)
        learnDestination(from: trip)
        trip.updatedAt = .now
        try? context.save()
        recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
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
        switch recorder.state {
        case .idle:
            isRecording = false
            isTripPaused = false
        case .recording:
            isRecording = true
            isTripPaused = false
        case .paused:
            isRecording = true
            isTripPaused = true
        }
        // Read from the recorder, not from `state`: `RecorderState.distanceMeters` is zero
        // while paused, and a driver waiting at a light must not watch it drop to 0 km.
        activeDistanceMeters = recorder.currentDistanceMeters
        activeStartedAt = recorder.startedAt
        activeRoute = recorder.routeSamples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if isRecording, let startedAt = activeStartedAt {
            liveActivity.update(
                distanceMeters: activeDistanceMeters,
                startedAt: startedAt,
                unit: settingsStore.settings.distanceUnit
            )
        }
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
        let yearly = ReportBuilder.yearlyDistanceMeters(
            before: trip, in: allTrips,
            window: taxYearWindow(for: trip.countryCode, containing: trip.startedAt)
        )

        let calculation = rule.calculate(
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle(for: trip.vehicleID),
            date: trip.startedAt,
            yearlyDistanceMeters: yearly
        )

        // No applicable scale and no rate the user set: the amount is *unknown*, not zero.
        // Writing 0,00 € put a precise-looking figure on a report — trips outside a pack's
        // validity window, and vehicles no published scale covers, all came out as zero.
        let hasUsableRate = calculation.isOfficial || calculation.rate > 0
        trip.mileageRate = hasUsableRate ? calculation.rate : nil
        trip.calculatedAmount = hasUsableRate ? calculation.amount : nil
        trip.mileageUnit = hasUsableRate ? calculation.unit : nil
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
        // The unit the rate was frozen in, never the one Settings currently displays.
        let unit = trip.mileageUnit ?? settingsStore.settings.distanceUnit
        let distance = Decimal(unit.value(fromMeters: trip.distanceMeters))
        trip.calculatedAmount = MileageRounding.money(distance * rate)
        trip.updatedAt = .now
        try? context.save()
        recorderRevision += 1
    }

    /// The window a country's allowance counts over — 6 April in Britain, 1 July in
    /// Australia, 1 January almost everywhere else. Falls back to the calendar year for a
    /// country with no pack, where nothing accumulates anyway.
    func taxYearWindow(for countryCode: String, containing date: Date) -> Range<Date> {
        if let pack = ruleEngine.officialPack(for: countryCode, on: date) {
            return pack.taxYearRange(containing: date)
        }
        if let anyVersion = ruleEngine.anyPack(for: countryCode) {
            return anyVersion.taxYearRange(containing: date)
        }
        return ReportPeriod.year(Calendar.current.component(.year, from: date)).range()
    }

    /// Re-runs the arithmetic of every business trip in a tax year, under each trip's own
    /// frozen rule.
    ///
    /// A tiered scale prices a trip by where the year had already got to — the 10 000th mile,
    /// the 5 000th kilometre. So inserting a backdated trip, deleting one, or correcting a
    /// distance moves every later trip of that year onto a different band, and they kept
    /// their old figure: arithmetic that had quietly stopped adding up.
    ///
    /// This is not the forbidden silent re-rating. Each trip is recomputed with the *same*
    /// `mileageRuleVersion` it was saved with; only its position in the year changes. A flat
    /// rate is skipped entirely, because nothing there depends on the year.
    func recalculateCumulativeYear(containing date: Date, countryCode: String) {
        guard ruleEngine.hasCumulativeScale(country: countryCode) else { return }

        let window = taxYearWindow(for: countryCode, containing: date)
        let all = (try? context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let affected = all.filter {
            $0.tripType == .business
                && $0.countryCode.caseInsensitiveCompare(countryCode) == .orderedSame
                && window.contains($0.startedAt)
        }
        guard !affected.isEmpty else { return }

        var cumulative: Double = 0
        for trip in affected {
            if let version = trip.mileageRuleVersion,
               let frozen = ruleEngine.pack(country: trip.countryCode, version: version) {
                let calculation = DeclarativeMileageRule(pack: frozen).calculate(
                    distanceMeters: trip.distanceMeters,
                    vehicle: vehicle(for: trip.vehicleID),
                    date: trip.startedAt,
                    yearlyDistanceMeters: cumulative
                )
                if calculation.isOfficial {
                    trip.mileageRate = calculation.rate
                    trip.calculatedAmount = calculation.amount
                    trip.currencyCode = calculation.currencyCode
                    trip.mileageUnit = calculation.unit
                    trip.updatedAt = .now
                    // Only kilometres actually priced under the scale consume its allowance.
                    // A trip outside every validity window has no official amount, so it is
                    // not part of the year the scale is counting.
                    cumulative += trip.distanceMeters
                }
            }
        }
        try? context.save()
        invalidate()
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
        settingsStore.save()
        applyNotificationPreferences()
    }

    /// Brings the scheduled notifications in line with the two switches in Settings. Called
    /// whenever either is flipped, so turning the monthly reminder off actually cancels it
    /// rather than leaving it queued for the 1st.
    func applyNotificationPreferences() {
        let settings = settingsStore.settings
        if settings.notificationsEnabled, settings.monthlyReportReminderEnabled {
            notifications.scheduleMonthlyReportReminder()
        } else {
            notifications.cancelMonthlyReportReminder()
        }
        if !(settings.notificationsEnabled && settings.tripReminderEnabled) {
            notifications.cancelTripReminders()
        }
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
