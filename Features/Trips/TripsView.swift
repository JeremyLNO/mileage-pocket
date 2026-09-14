import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var filter: TripType?
    @State private var showsManualEntry = false
    @State private var showsPaywall = false

    private var settings: UserSettings { dependencies.settingsStore.settings }

    private var filtered: [Trip] {
        trips
            .filter { $0.endedAt != nil }
            .filter { filter == nil || $0.tripType == filter }
            .filter { trip in
                guard !search.isEmpty else { return true }
                let haystack = [trip.startAddress, trip.endAddress, trip.purpose].compactMap { $0 }.joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(search)
            }
    }

    /// Trips recorded and never qualified. Derived from the live query so a trip that
    /// leaves the queue makes the banner shrink under the thumb that emptied it.
    private var awaitingReview: [Trip] {
        trips.filter { !$0.isReviewed && $0.endedAt != nil }
    }

    /// One line at the top of the list, and only when there is something in it. It is an
    /// entrance, not a copy: showing the trips here as well as in their own date section
    /// would make one drive look like two.
    @ViewBuilder
    private var reviewBanner: some View {
        if !awaitingReview.isEmpty {
            Button {
                path.append(ReviewQueueRoute())
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(Theme.signal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: L.format("trips.review.count", awaitingReview.count))
                            .scaledFont(16, relativeTo: .body, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                        Text("trips.review.subtitle")
                            .scaledFont(13, relativeTo: .footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reviewQueueBanner")
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if filtered.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "trips.empty.title",
                        message: "trips.empty.message"
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        reviewBanner
                        ForEach(TripGrouping.group(filtered), id: \.0) { section, sectionTrips in
                            Section(LocalizedStringKey(section.titleKey)) {
                                ForEach(sectionTrips) { trip in
                                    NavigationLink(value: trip.id) {
                                        TripRow(trip: trip, unit: settings.distanceUnit)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationDestination(for: ReviewQueueRoute.self) { _ in ReviewQueueView() }
            .navigationDestination(for: Trip.ID.self) { id in
                if let trip = filtered.first(where: { $0.id == id }) {
                    TripDetailView(trip: trip)
                }
            }
            .background(Theme.background)
            .navigationTitle("tab.trips")
            .searchable(text: $search, prompt: Text("trips.search"))
            .task {
                // Screenshot hook only — compiled out of Release with the rest of DemoMode.
                guard DemoMode.opensLastTrip, path.isEmpty, let first = filtered.first else { return }
                path.append(first.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("trips.filter", selection: $filter) {
                            Text("trips.filter.all").tag(TripType?.none)
                            Text("trip.type.business").tag(TripType?.some(.business))
                            Text("trip.type.personal").tag(TripType?.some(.personal))
                        }
                    } label: {
                        Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if dependencies.canAccess(.manualTrip) {
                            showsManualEntry = true
                        } else {
                            showsPaywall = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("trips.add.manual"))
                }
            }
            .sheet(isPresented: $showsManualEntry) { ManualTripView() }
            .sheet(isPresented: $showsPaywall) { PaywallView() }
        }
    }
}

/// Route marker for the qualification queue. A type of its own rather than a boolean, so
/// the navigation stack keeps one meaning per value.
private struct ReviewQueueRoute: Hashable {}

private struct TripRow: View {
    let trip: Trip
    let unit: DistanceUnit
    @Environment(\.locale) private var locale
    @Environment(AppDependencies.self) private var dependencies

    private var labels: (start: String, end: String) { dependencies.endpointLabels(for: trip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(labels.start) → \(labels.end)")
                    .scaledFont(16, relativeTo: .body, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                TripTypePill(type: trip.tripType)
            }
            HStack(spacing: 8) {
                Text(trip.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                Text("•")
                Text(Fmt.distance(meters: trip.distanceMeters, unit: unit, locale: locale)).monospacedDigit()
                if let amount = trip.calculatedAmount, let currency = trip.currencyCode, amount > 0 {
                    Text("•")
                    Text(Fmt.money(amount, currencyCode: currency, locale: locale)).monospacedDigit()
                }
            }
            .scaledFont(13, relativeTo: .footnote)
            .foregroundStyle(Theme.textSecondary)

            if let purpose = trip.purpose, !purpose.isEmpty {
                Text(purpose)
                    .scaledFont(13, relativeTo: .footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
