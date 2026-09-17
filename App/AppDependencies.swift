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
    /// Watches for the phone being plugged into a car.
    let carConnection: any CarConnectionObserving
    /// Watches for the phone's owner driving, plugged in or not.
    let driveDetector: any DriveDetecting
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
    /// The distance every surface shows — the driving screen, the lock screen, CarPlay.
    ///
    /// Deliberately **not** the recorder's live value. That one moves on every accepted fix,
    /// while the Live Activity moved on a schedule of its own, and the two disagreed by a few
    /// hundred metres at any given instant. `DistanceBroadcast` holds the schedule now, once,
    /// and this is what it publishes.
    private(set) var activeDistanceMeters: Double = 0
    private(set) var activeStartedAt: Date?
    /// The schedule the figure above changes on: every 100 m, or every 5 s.
    private var broadcast = DistanceBroadcast()
    /// Where a widget tap asked the app to go, honoured once by whichever screen owns it.
    ///
    /// A deep link cannot push a view from the app's entry point — the tab and its
    /// navigation stack belong to `MainTabView` and `TripsView`. So the intent is parked
    /// here and consumed there.
    enum DeepLink: Equatable { case reviewQueue }
    var pendingDeepLink: DeepLink?

    /// Set when a trip could not start because location is off or refused. The view shows it;
    /// before, the app opened its driving screen and recorded nothing, saying nothing.
    var locationRefused = false
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

    /// The clock, injectable so the publication schedule and the CarPlay grace period can be
    /// tested without waiting them out in real seconds.
    private let now: () -> Date

    /// The one live instance, for the scene delegates UIKit builds by itself.
    ///
    /// The whole app is otherwise wired by injection — views never reach for a shared
    /// anything, which is what lets every service be swapped in tests. `CPTemplateApplicationScene`
    /// breaks that: UIKit instantiates the delegate from the Info.plist and there is no seam
    /// to pass anything through. This is the escape hatch for that single case, and
    /// `CarPlaySceneDelegate` is its only reader.
    private(set) static weak var current: AppDependencies?

    init(
        container: ModelContainer,
        storeHealth: StoreHealth = .healthy,
        recorderFactory: ((ModelContext) -> any TripRecording)? = nil,
        carConnectionMonitor: (any CarConnectionObserving)? = nil,
        driveDetector: (any DriveDetecting)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.container = container
        self.storeHealth = storeHealth
        self.now = now
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
        self.carConnection = carConnectionMonitor ?? CarConnectionMonitor()
        self.driveDetector = driveDetector ?? DriveDetector()
        self.recorder = recorderFactory?(context) ?? TripRecorder(
            context: context,
            provider: CoreLocationProvider(),
            geocoder: GeocodingService()
        )

        // Last: `self` is not usable until every stored property is initialised.
        Self.current = self
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
            // The answer to the first prompt is the only moment iOS will show the second.
            escalateToAlwaysIfNeeded()
            // Always may have just been granted — or withdrawn in Settings. The standing
            // watch exists only under Always, so it is re-decided here rather than assumed
            // from what was true at launch.
            applyBackgroundWatch()
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
        #if DEBUG
        // Avant tout le reste : ces objets n'existent que pour que CloudKit fabrique leur
        // type d'enregistrement, et ils repartent au lancement suivant.
        if CloudKitSchemaSeed.isRequested { CloudKitSchemaSeed.insertOneOfEachModel(context: context) }
        if CloudKitSchemaSeed.isCleanupRequested { CloudKitSchemaSeed.removeSeed(context: context) }
        #endif
        applyDebugOnboardingState()
        subscriptions.start()
        adoptTripInProgress()
        syncRecorderState()
        // What was decided on the home screen while the app was not running. Before the
        // snapshot below, so a launch never rewrites a question the user already answered.
        WidgetActionBridge.applyPendingActions = { [weak self] in self?.applyPendingWidgetActions() }
        applyPendingWidgetActions()
        // Written at every launch, not only when a trip ends. Otherwise the widget of someone
        // who installs the update stays blank until their next finished drive — with a store
        // full of trips it could have been describing all along.
        refreshWidgetSnapshot()
        startWatchingForCarPlay()
        applyBackgroundWatch()
        applyDriveDetection()
        exportDemoReportIfRequested()
        // Fire-and-forget: a rule pack refresh must never hold up a launch, and the endpoint
        // is not deployed yet, so failing is the expected path in V1.
        Task.detached(priority: .background) { [rulePackUpdater] in
            await rulePackUpdater?.refresh()
        }
    }

    /// Plugging into CarPlay is the one moment the app can know a drive is beginning without
    /// being asked. Watching costs nothing — the route is already being tracked by the
    /// system — so the observer runs whatever the setting says; only the *action* is gated,
    /// which is what lets the switch take effect without a relaunch.
    private func startWatchingForCarPlay() {
        carConnection.onChange = { [weak self] connected in
            self?.carPlayConnectionChanged(connected)
        }
        carConnection.start()
        // A launch that happens *because* the phone was plugged in arrives with the route
        // already established, so there is no change to wait for.
        if carConnection.isConnected { carPlayConnectionChanged(true) }
    }

    /// How long the signal has to stay gone before the trip it started is ended.
    ///
    /// Neither signal is a seatbelt sensor. The audio route drops for a phone call, for Siri,
    /// when the head unit switches to radio, when a wireless link stutters at a junction; the
    /// motion classifier hesitates at every long red light. Every one of those used to end
    /// the drive on the spot, silently, mid-motorway. Ninety seconds covers all of them and
    /// still ends the trip while the driver is walking away from the car.
    static let autoStopGrace: TimeInterval = 90
    /// Metres of progress during the grace period that prove the car is still driving. A
    /// stationary phone drifts by a few metres; fifty is movement.
    static let stillDrivingMeters: Double = 50

    /// Set while the end of a drive is waiting to be confirmed.
    private var pendingAutoStop: Task<Void, Never>?
    /// What the motion classifier last said, so the confirmation can ask both signals rather
    /// than only the one that went quiet.
    private(set) var isDrivingDetected = false
    /// Distance at the moment the car disappeared, to tell "parked" from "still driving".
    private var distanceAtDisconnect: Double = 0
    /// Whether the trip in progress was started by the car rather than by the driver.
    ///
    /// Automatic stopping belongs to automatic starting. A drive the driver began by hand is
    /// theirs to end, and unplugging at a petrol station must not decide otherwise.
    private(set) var tripWasAutoStarted = false

    /// Whether a trip begun from the car will actually receive positions.
    ///
    /// Always, and only Always. See `carPlayConnectionChanged` for why.
    var canRecordFromCar: Bool {
        recorder.authorizationStatus == .authorizedAlways
    }

    func carPlayConnectionChanged(_ connected: Bool) {
        let settings = settingsStore.settings
        if connected {
            // Back before the grace ran out: whatever the drop was, it was not the end of the
            // drive.
            cancelPendingAutoStop()
            guard settings.autoStartOnCarPlay, !isRecording, canAccess(.startTrip) else { return }
            // Nothing is started without Always. "While Using" permits background updates
            // only for a session that began while the app was in use; one begun on a CarPlay
            // connection, phone locked, gets no positions at all — a running clock over a
            // 0.0 km trip, which is worse than not starting.
            guard canRecordFromCar else { return }
            startTrip()
            // Only if it actually started: a refused permission leaves nothing running, and
            // marking it automatic would arm a stop for a trip that does not exist.
            tripWasAutoStarted = isRecording
        } else {
            guard settings.autoStartOnCarPlay, settings.autoStopOnCarPlayDisconnect else { return }
            armAutoStop()
        }
    }

    /// The motion classifier changed its mind about what its owner is doing.
    func drivingStateChanged(_ state: DriveSignal.State) {
        isDrivingDetected = (state == .driving)
        guard settingsStore.settings.autoStartOnDriving else { return }
        switch state {
        case .driving:
            cancelPendingAutoStop()
            guard !isRecording, canAccess(.startTrip) else { return }
            startTrip()
            tripWasAutoStarted = isRecording
        case .notDriving:
            // Same confirmation as a head unit going quiet, and for the same reason: the
            // classifier hesitates at long red lights, and a drive must not end at one.
            armAutoStop()
        case .unknown:
            break
        }
    }

    /// Opens the window at the end of which a self-started trip is ended, unless something
    /// says the drive is still going.
    private func armAutoStop() {
        guard isRecording, tripWasAutoStarted, pendingAutoStop == nil else { return }
        distanceAtDisconnect = recorder.currentDistanceMeters
        pendingAutoStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoStopGrace))
            guard !Task.isCancelled else { return }
            self?.confirmAutoStop()
        }
    }

    /// Decides, once the grace has run out, whether the drive really is over.
    ///
    /// Internal rather than private: this is the half of the rule worth testing, and waiting
    /// ninety real seconds in a test is not a test.
    func confirmAutoStop() {
        pendingAutoStop = nil
        guard isRecording, tripWasAutoStarted else { return }
        // Either signal is enough to keep the trip alive. They answer different questions —
        // "is this phone in that car" and "is this person driving" — and a drive is over only
        // when neither of them says otherwise.
        guard !carConnection.isConnected, !isDrivingDetected else { return }
        guard settingsStore.settings.autoStopOnCarPlayDisconnect else { return }

        // Still covering ground with both signals quiet: a dropped link and a hesitant
        // classifier, not a parked car. Give it another window rather than cutting a drive
        // in half.
        if recorder.currentDistanceMeters - distanceAtDisconnect >= Self.stillDrivingMeters {
            distanceAtDisconnect = recorder.currentDistanceMeters
            pendingAutoStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.autoStopGrace))
                guard !Task.isCancelled else { return }
                self?.confirmAutoStop()
            }
            return
        }
        stopTrip()
    }

    private func cancelPendingAutoStop() {
        pendingAutoStop?.cancel()
        pendingAutoStop = nil
    }

    /// Starts or stops watching the motion classifier, according to the switch and to what
    /// the hardware offers. Idempotent, like the background watch.
    func applyDriveDetection() {
        guard settingsStore.settings.autoStartOnDriving, driveDetector.isAvailable else {
            driveDetector.stop()
            return
        }
        driveDetector.onChange = { [weak self] state in self?.drivingStateChanged(state) }
        driveDetector.start()
    }

    /// The switch that lets a trip begin in any car, not only one with CarPlay.
    func setAutoStartOnDriving(_ enabled: Bool) {
        settingsStore.settings.autoStartOnDriving = enabled
        settingsStore.save()
        if enabled, recorder.authorizationStatus != .authorizedAlways {
            // Same reason as the CarPlay switch: without Always the app is not woken at the
            // start of a drive, and the detector only ever sees the drives it was already
            // awake for.
            recorder.requestPermission()
        }
        applyBackgroundWatch()
        applyDriveDetection()
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
        // Cleared first, set again by the CarPlay path if that is who is calling: a trip is
        // the driver's until proven automatic.
        tripWasAutoStarted = false
        do {
            try recorder.start(vehicleID: vehicleID)
            broadcast.begin(at: now())
            activeDistanceMeters = 0
            liveActivity.start(
                vehicleName: activeVehicleName ?? L.string("home.no.vehicle"),
                unit: settingsStore.settings.distanceUnit,
                startedAt: recorder.startedAt ?? now()
            )
            if settingsStore.settings.notificationsEnabled, settingsStore.settings.tripReminderEnabled {
                notifications.scheduleTripStillRunningReminder()
            }
            // After `syncRecorderState`, never before it. The snapshot is built from
            // `isRecording` and `activeStartedAt`, and those are set *there* — refreshing
            // first wrote "no trip in progress" at the exact moment one began, and the
            // widget then said nothing was happening for the whole drive.
            syncRecorderState()
            refreshWidgetSnapshot()
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
        let startedAt = recorder.startedAt ?? now()
        let unit = settingsStore.settings.distanceUnit
        cancelPendingAutoStop()
        tripWasAutoStarted = false

        do {
            let trip = try recorder.stop()
            // The schedule is for a drive in progress. What a finished trip shows is what was
            // written to it — the summary sheet and the lock screen's last frame must not be
            // five seconds short of the figure in the log.
            broadcast.settle(on: trip.distanceMeters, now: now())
            activeDistanceMeters = broadcast.publishedMeters
            // Saved outright. Stopping used to open a summary sheet that had to be filled in
            // before the trip counted — four taps for a drive, and, stopped from CarPlay, a
            // modal left waiting on a phone in a pocket. The trip is written with the
            // default classification and enters the review queue, where the tab badge asks
            // for the one answer that matters, when the driver is no longer driving.
            applyCalculation(to: trip)
            try? context.save()
            recalculateCumulativeYear(containing: trip.startedAt, countryCode: trip.countryCode)
            // The addresses are fetched after the trip is on screen. Reverse-geocoding is two
            // network calls with no deadline of their own; making STOP wait for them meant a
            // driver pressing Stop and watching a frozen screen for several seconds.
            Task { [recorder] in
                await recorder.attachPlaces(to: trip)
                // Again once the addresses are in: the widget names the trip it asks about
                // by where it went, and at the moment STOP was pressed nothing knew that yet.
                refreshWidgetSnapshot()
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
        liveActivity.end(
            distanceMeters: activeDistanceMeters,
            startedAt: startedAt,
            unit: unit,
            locale: localization.locale
        )
        notifications.cancelTripReminders()
        // The trip's own use of the receiver has just been torn down; the standing watch is
        // a separate promise and has to survive it.
        applyBackgroundWatch()
        syncRecorderState()
        // Same ordering as `startTrip`, for the same reason: written before this, the
        // snapshot still carried `isRecording == true` and the old start date, so the home
        // screen kept counting a drive that had just ended — with a STOP on it.
        refreshWidgetSnapshot()
    }

    /// Arms or disarms the watch that lets iOS relaunch the app at the start of a drive.
    ///
    /// Idempotent and called from everywhere the answer can change: launch, a permission
    /// granted or withdrawn, the switch being flipped, the end of a trip. Cheaper to re-apply
    /// than to reason about which of those actually moved it.
    func applyBackgroundWatch() {
        let settings = settingsStore.settings
        recorder.setBackgroundWatch(
            BackgroundWatch.shouldWatch(
                // Either switch needs it: the watch is what wakes a closed app at the start
                // of a drive, and both signals are read only once the app is awake.
                autoStartEnabled: settings.autoStartOnCarPlay || settings.autoStartOnDriving,
                authorization: recorder.authorizationStatus
            )
        )
    }

    /// The CarPlay automatic-start switch, with everything that hangs off it.
    ///
    /// Turning it on asks for **Always** when the app does not have it yet: without that
    /// authorisation the switch keeps a promise it cannot keep — automatic starting would go
    /// on working only while the app happened to be alive, which is exactly the complaint it
    /// is meant to answer. The prompt is raised here, on an explicit gesture, and never at
    /// launch.
    func setAutoStartOnCarPlay(_ enabled: Bool) {
        settingsStore.settings.autoStartOnCarPlay = enabled
        settingsStore.save()
        if enabled, recorder.authorizationStatus != .authorizedAlways {
            recorder.requestPermission()
        }
        applyBackgroundWatch()
    }

    /// The last trip that can still be picked up where it left off, if there is one.
    ///
    /// Exists because a drive that ends on its own is not a rare accident: a CarPlay link
    /// drops, iOS reclaims the app, a thumb finds STOP in a pocket. Without this the driver's
    /// only repair is a second trip beside the first and a manual addition on a document that
    /// has to add up.
    var resumableTrip: Trip? {
        guard !isRecording else { return nil }
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let trips = (try? context.fetch(descriptor)) ?? []
        return trips.first { TripRecorder.canResume($0, now: now()) }
    }

    /// Re-opens a finished trip and goes on recording into it.
    func resumeTrip(_ trip: Trip) {
        guard !isRecording else { return }
        if recorder.authorizationStatus == .notDetermined {
            recorder.requestPermission()
        }
        tripWasAutoStarted = false
        do {
            try recorder.resume(trip)
            // Published at once, without waiting for the schedule: the driver pressed
            // Continue on a figure and must find that same figure on the driving screen.
            broadcast.settle(on: recorder.currentDistanceMeters, now: now())
            activeDistanceMeters = broadcast.publishedMeters
            liveActivity.start(
                vehicleName: activeVehicleName ?? L.string("home.no.vehicle"),
                unit: settingsStore.settings.distanceUnit,
                startedAt: recorder.startedAt ?? now(),
                locale: localization.locale
            )
            liveActivity.update(
                distanceMeters: activeDistanceMeters,
                startedAt: recorder.startedAt ?? now(),
                unit: settingsStore.settings.distanceUnit,
                locale: localization.locale
            )
            if settingsStore.settings.notificationsEnabled, settingsStore.settings.tripReminderEnabled {
                notifications.scheduleTripStillRunningReminder()
            }
            // The widget's whole job while a trip runs is to say that one is running.
            refreshWidgetSnapshot()
            syncRecorderState()
        } catch RecorderError.locationUnavailable {
            locationRefused = true
            syncRecorderState()
        } catch {
            syncRecorderState()
        }
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
        let measured = recorder.currentDistanceMeters
        activeStartedAt = recorder.startedAt
        activeRoute = recorder.routeSamples.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if isRecording {
            // One decision, then the same number handed to everything that displays it. The
            // Live Activity is only pushed when the published figure actually moved, which
            // is also what keeps ActivityKit from rate-limiting the trip into a freeze.
            if broadcast.consider(measured, now: now()) {
                activeDistanceMeters = broadcast.publishedMeters
                if let startedAt = activeStartedAt {
                    liveActivity.update(
                        distanceMeters: activeDistanceMeters,
                        startedAt: startedAt,
                        unit: settingsStore.settings.distanceUnit,
                        locale: localization.locale
                    )
                }
            }
        } else {
            activeDistanceMeters = measured
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

    private enum LocationPermissionKey {
        static let askedForAlways = "location.askedForAlways"
    }

    /// Whether iOS has already been asked to upgrade "While Using" to "Always".
    ///
    /// It shows that prompt **once**. Every later call to
    /// `requestAlwaysAuthorization()` returns silently, so a button that offers to ask again
    /// would do nothing at all — the only way through from there is iOS Settings, and the UI
    /// has to send the driver there instead of pretending.
    var hasAskedForAlwaysAuthorization: Bool {
        UserDefaults.standard.bool(forKey: LocationPermissionKey.askedForAlways)
    }

    /// True when asking again can still produce a system prompt.
    var canStillAskForAlways: Bool {
        switch recorder.authorizationStatus {
        case .notDetermined: return true
        case .authorizedWhenInUse: return !hasAskedForAlwaysAuthorization
        default: return false
        }
    }

    func requestLocationPermission() {
        if recorder.authorizationStatus == .authorizedWhenInUse {
            UserDefaults.standard.set(true, forKey: LocationPermissionKey.askedForAlways)
        }
        recorder.requestPermission()
    }

    /// Escalates to Always the moment "While Using" is granted.
    ///
    /// iOS refuses to jump straight to Always: the first prompt can only ever be the
    /// While-Using one, and the upgrade has to be a second request. Without this second step
    /// the app sat on "While Using" forever — which records a drive begun from the phone and
    /// records **nothing at all** from a drive begun on the car's screen.
    private func escalateToAlwaysIfNeeded() {
        guard recorder.authorizationStatus == .authorizedWhenInUse,
              !hasAskedForAlwaysAuthorization else { return }
        requestLocationPermission()
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
        // The same switch drives the remote ones. Without this, turning notifications off
        // silenced the app's own reminders while Crazy Bee Labs announcements kept arriving
        // — the setting would have been telling the truth about half of itself.
        OneSignalPush.setOptedIn(settings.notificationsEnabled)
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
