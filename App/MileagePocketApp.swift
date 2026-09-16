import SwiftUI
import SwiftData

@main
struct MileagePocketApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // iCloud is read from UserDefaults rather than the store, because the store cannot be
        // opened before this decision is made.
        let cloudEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        let opening = PersistenceController.openStore(cloudKitEnabled: cloudEnabled)
        let dependencies = AppDependencies(container: opening.container, storeHealth: opening.health)
        // Bootstrapped here rather than only from the root view: when iOS relaunches the app
        // in the background after a significant location change — the app having been
        // terminated mid-drive — no window is built, so a `task` on a view would never run
        // and the trip would stay dead until the user opened the app themselves. It is a
        // no-op the second time.
        dependencies.bootstrap()
        _dependencies = State(initialValue: dependencies)
        // Crazy Bee Labs announcements; inert until an App ID is configured. Trip
        // reminders stay local and never go through OneSignal.
        OneSignalPush.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .modelContainer(dependencies.container)
                .task { dependencies.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    // A widget button tapped while the app sat in the background reaches a
                    // process that will not bootstrap again. This is the other half of that
                    // pair — without it, a trip classified from the home screen would stay
                    // classified only in the widget until the app was killed and relaunched.
                    guard phase == .active else { return }
                    dependencies.applyPendingWidgetActions()
                }
                .onOpenURL { url in
                    // The widget lands the reader where its own headline pointed: a drive
                    // under way opens the driving screen, a queue opens the queue, and
                    // otherwise the tap starts a trip. Sending every tap to Home made the
                    // widget a decoration with a shortcut attached.
                    switch url.host {
                    case "start":
                        if dependencies.canAccess(.startTrip), !dependencies.isRecording {
                            dependencies.startTrip()
                        }
                    case "review":
                        dependencies.pendingDeepLink = .reviewQueue
                    case "trip":
                        // `isRecording` already puts `ActiveTripView` on screen; opening the
                        // app is the whole action.
                        break
                    default:
                        break
                    }
                }
        }
    }
}
