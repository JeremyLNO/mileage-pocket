import SwiftUI

/// Decides what the app shows: onboarding, the tabs, the live trip screen, or the summary
/// sheet that follows a trip. Nothing else in the app makes that decision.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var dependencies = dependencies

        Group {
            if !dependencies.settingsStore.settings.hasCompletedOnboarding {
                OnboardingFlow()
            } else if dependencies.isRecording {
                ActiveTripView()
            } else {
                MainTabView()
            }
        }
        // Language is applied here, once: every view below reads `\.locale`, so switching in
        // Settings re-renders the app without a relaunch.
        .environment(\.locale, dependencies.localization.locale)
        .sheet(item: $dependencies.finishedTrip) { trip in
            TripSummarySheet(trip: trip)
        }
        .animation(.snappy(duration: 0.25), value: dependencies.isRecording)
    }
}
