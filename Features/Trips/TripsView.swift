import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
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

    var body: some View {
        NavigationStack {
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
                        ForEach(TripGrouping.group(filtered), id: \.0) { section, sectionTrips in
                            Section(LocalizedStringKey(section.titleKey)) {
                                ForEach(sectionTrips) { trip in
                                    NavigationLink { TripDetailView(trip: trip) } label: {
                                        TripRow(trip: trip, unit: settings.distanceUnit)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Theme.background)
            .navigationTitle("tab.trips")
            .searchable(text: $search, prompt: Text("trips.search"))
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
