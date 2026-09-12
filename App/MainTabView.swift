import SwiftUI

/// Four tabs, no more. Everything a daily user does lives one tap from here, and the tab
/// bar is the only navigation chrome in the app.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selection = DemoMode.initialTab ?? "home"

    var body: some View {
        TabView(selection: $selection) {
            Tab("tab.home", systemImage: "car.fill", value: "home") {
                HomeView()
            }
            Tab("tab.trips", systemImage: "list.bullet", value: "trips") {
                TripsView()
            }
            Tab("tab.reports", systemImage: "doc.text", value: "reports") {
                ReportsView()
            }
            Tab("tab.settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .tint(Theme.signal)
    }
}
