import SwiftData
import SwiftUI

/// The pile of drives nobody has said anything about yet.
///
/// A trip carries a type whether or not anyone chose one, so an unqualified trip is
/// indistinguishable, on a claim, from a business one — it simply arrives as whatever the
/// default was. That is the quiet way a mileage log stops being true: not by recording
/// badly, but by recording without being told what it recorded.
///
/// So the pile is visible, counted on the tab bar, and emptied in one sitting: two targets
/// per trip, no navigation, no keyboard. Anything more detailed is one tap away on the trip
/// itself, and can wait.
struct ReviewQueueView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]

    private var settings: UserSettings { dependencies.settingsStore.settings }

    /// Derived from the live query rather than from a fetch: a trip qualified here has to
    /// leave the list under the thumb that qualified it.
    private var queue: [Trip] {
        trips.filter { !$0.isReviewed && $0.endedAt != nil }
    }

    var body: some View {
        Group {
            if queue.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "review.empty.title",
                    message: "review.empty.message"
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(queue) { trip in
                            row(for: trip)
                        }
                    } footer: {
                        Text("review.hint")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Theme.background)
        .navigationTitle("review.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                TripDetailView(trip: trip)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: endpoints(of: trip))
                        .scaledFont(16, relativeTo: .body, weight: .semibold)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(trip.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        Text("•")
                        Text(Fmt.distance(meters: trip.distanceMeters, unit: settings.distanceUnit, locale: locale))
                            .monospacedDigit()
                    }
                    .scaledFont(13, relativeTo: .footnote)
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                choice(.business, for: trip, systemImage: "briefcase.fill", tint: Theme.business)
                choice(.personal, for: trip, systemImage: "house.fill", tint: Theme.personal)
            }
        }
        .padding(.vertical, 6)
    }

    private func choice(
        _ type: TripType,
        for trip: Trip,
        systemImage: String,
        tint: Color
    ) -> some View {
        Button {
            dependencies.reviewTrip(trip, as: type)
        } label: {
            Label(type == .business ? "trip.type.business" : "trip.type.personal", systemImage: systemImage)
                .scaledFont(15, relativeTo: .subheadline, weight: .semibold)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(type == .business ? "reviewBusiness" : "reviewPersonal")
    }

    private func endpoints(of trip: Trip) -> String {
        let labels = dependencies.endpointLabels(for: trip)
        return "\(labels.start) → \(labels.end)"
    }
}
