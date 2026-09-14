import SwiftData
import SwiftUI

/// Four tabs, no more. Everything a daily user does lives one tap from here, and the tab
/// bar is the only navigation chrome in the app.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selection = DemoMode.initialTab ?? "home"

    /// Trips recorded and never qualified. A count on the tab is the only reminder that
    /// costs nothing: a claim is worth what its completeness allows, and the drives nobody
    /// classified are the ones that quietly arrive as whatever the default was.
    @Query(filter: #Predicate<Trip> { $0.isReviewed == false && $0.endedAt != nil })
    private var awaitingReview: [Trip]

    var body: some View {
        TabView(selection: $selection) {
            Tab("tab.home", systemImage: "car.fill", value: "home") {
                HomeView()
            }
            Tab("tab.trips", systemImage: "list.bullet", value: "trips") {
                TripsView()
            }
            .badge(awaitingReview.count)
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
