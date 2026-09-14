import SwiftUI
import SwiftData

@main
struct MileagePocketApp: App {
    @State private var dependencies: AppDependencies

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
                .onOpenURL { url in
                    // mileagepocket://start — the widget's Start Trip action.
                    guard url.host == "start" || url.path == "/start" else { return }
                    if dependencies.canAccess(.startTrip), !dependencies.isRecording {
                        dependencies.startTrip()
                    }
                }
        }
    }
}
