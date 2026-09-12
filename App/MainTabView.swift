import SwiftUI

/// Four tabs, no more. Everything a daily user does lives one tap from here, and the tab
/// bar is the only navigation chrome in the app.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TabView {
            Tab("tab.home", systemImage: "car.fill") {
                HomeView()
            }
            Tab("tab.trips", systemImage: "list.bullet") {
                TripsView()
            }
            Tab("tab.reports", systemImage: "doc.text") {
                ReportsView()
            }
            Tab("tab.settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Theme.signal)
    }
}
