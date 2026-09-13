import SwiftUI
import SwiftData

@main
struct MileagePocketApp: App {
    @State private var dependencies: AppDependencies

    init() {
        // iCloud is read from UserDefaults rather than the store, because the store cannot be
        // opened before this decision is made.
        let cloudEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        let container = PersistenceController.makeContainerWithFallback(cloudKitEnabled: cloudEnabled)
        _dependencies = State(initialValue: AppDependencies(container: container))
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
