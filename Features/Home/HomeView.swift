import SwiftUI
import SwiftData

/// The screen someone opens with one hand while sitting down in a car. One control matters,
/// and it is the biggest thing on the screen.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var model: HomeModel?
    @State private var showsVehiclePicker = false
    @State private var showsPaywall = false

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    private var settings: UserSettings { dependencies.settingsStore.settings }
    private var unit: DistanceUnit { settings.distanceUnit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    monthSummary
                    startControl
                    lastTripCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .navigationTitle("app.name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .task { refresh() }
        .onChange(of: dependencies.recorderRevision) { _, _ in refresh() }
        .sheet(isPresented: $showsVehiclePicker) {
            VehiclePickerSheet(selection: Binding(
                get: { settings.defaultVehicleID },
                set: { newValue in
                    settings.defaultVehicleID = newValue
                    dependencies.settingsStore.save()
                }
            ))
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .alert("home.location.refused.title", isPresented: Binding(
            get: { dependencies.locationRefused },
            set: { if !$0 { dependencies.locationRefused = false } }
        )) {
            Button("home.location.refused.settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("common.cancel", role: .cancel) { dependencies.locationRefused = false }
        } message: {
            Text("home.location.refused.message")
        }
    }

    // MARK: - Sections

    private var monthSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model?.monthTitle ?? "").eyebrowStyle()

            MeterReadout(
                value: Fmt.distanceValue(meters: model?.monthDistanceMeters ?? 0, unit: unit, locale: locale, fractionDigits: 0),
                unit: Fmt.unitAbbreviation(unit, locale: locale),
                size: 72
            )

            if let model, model.monthAmount > 0 {
                Text(L.format("home.estimated", Fmt.money(model.monthAmount, currencyCode: model.currencyCode, locale: locale)))
                    .scaledFont(17, relativeTo: .body, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let model, model.businessTripCount > 0 {
                Text(L.plural("home.business.trips", model.businessTripCount))
                    .scaledFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var startControl: some View {
        VStack(spacing: 16) {
            DialButton(title: "home.start", subtitle: nil) {
                startTrip()
            }
            .accessibilityLabel(Text("home.start.accessibility"))

            // A drive that ended on its own is usually noticed later, from this screen. START
            // would open a second trip beside the first; this one goes on writing into it.
            if let resumable = dependencies.resumableTrip {
                Button { resumeTrip(resumable) } label: {
                    Label("home.continue", systemImage: "arrow.trianglehead.clockwise")
                        .scaledFont(15, relativeTo: .subheadline, weight: .semibold)
                        .foregroundStyle(Theme.signal)
                }
                .accessibilityIdentifier("continueLastTrip")
            }

            Button {
                showsVehiclePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "car.side.fill")
                    Text(activeVehicleName)
                    Image(systemName: "chevron.down").scaledFont(11, relativeTo: .caption2, weight: .semibold)
                }
                .scaledFont(15, relativeTo: .subheadline, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var lastTripCard: some View {
        if let trip = model?.lastTrip {
            NavigationLink {
                TripDetailView(trip: trip)
            } label: {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("home.last.trip").eyebrowStyle()
                        Text(verbatim: endpoints(of: trip))
                            .scaledFont(17, relativeTo: .body, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(Fmt.distance(meters: trip.distanceMeters, unit: unit, locale: locale))
                                .monospacedDigit()
                                .accessibilityIdentifier("lastTripDistance")
                            if let amount = trip.calculatedAmount, let currency = trip.currencyCode {
                                Text(Fmt.money(amount, currencyCode: currency, locale: locale))
                                    .monospacedDigit()
                            }
                            Spacer()
                            TripTypePill(type: trip.tripType)
                        }
                        .scaledFont(15, relativeTo: .subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Card {
                EmptyStateView(
                    systemImage: "road.lanes",
                    title: "home.empty.title",
                    message: "home.empty.message"
                )
            }
        }
    }

    // MARK: - Actions

    /// "Paris → Versailles" between towns; the two streets when both ends share a town, where
    /// the town alone would read "Paris → Paris" and say nothing.
    private func endpoints(of trip: Trip) -> String {
        let labels = dependencies.endpointLabels(for: trip)
        return "\(labels.start) → \(labels.end)"
    }

    private var activeVehicleName: String {
        if let id = settings.defaultVehicleID, let vehicle = vehicles.first(where: { $0.id == id }) {
            return vehicle.name
        }
        return vehicles.first(where: \.isDefault)?.name
            ?? vehicles.first?.name
            ?? L.string("home.no.vehicle")
    }

    private func resumeTrip(_ trip: Trip) {
        guard dependencies.canAccess(.startTrip) else {
            showsPaywall = true
            return
        }
        dependencies.resumeTrip(trip)
    }

    private func startTrip() {
        guard dependencies.canAccess(.startTrip) else {
            showsPaywall = true
            return
        }
        dependencies.startTrip()
    }

    private func refresh() {
        if model == nil { model = HomeModel(context: context) }
        model?.refresh(settings: settings)
    }
}
