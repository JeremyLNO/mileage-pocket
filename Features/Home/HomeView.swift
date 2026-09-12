import SwiftUI
import SwiftData

/// The screen someone opens with one hand while sitting down in a car. One control matters,
/// and it is the biggest thing on the screen.
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

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
                Text("home.estimated \(Fmt.money(model.monthAmount, currencyCode: model.currencyCode, locale: locale))")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let model, model.businessTripCount > 0 {
                Text("home.business.trips \(model.businessTripCount)")
                    .font(.system(size: 14))
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

            Button {
                showsVehiclePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "car.side.fill")
                    Text(activeVehicleName)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 15, weight: .medium))
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
                        Text("\(trip.startAddress ?? "—") → \(trip.endAddress ?? "—")")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(Fmt.distance(meters: trip.distanceMeters, unit: unit, locale: locale))
                                .monospacedDigit()
                            if let amount = trip.calculatedAmount, let currency = trip.currencyCode {
                                Text(Fmt.money(amount, currencyCode: currency, locale: locale))
                                    .monospacedDigit()
                            }
                            Spacer()
                            TripTypePill(type: trip.tripType)
                        }
                        .font(.system(size: 15))
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

    private var activeVehicleName: String {
        if let id = settings.defaultVehicleID, let vehicle = vehicles.first(where: { $0.id == id }) {
            return vehicle.name
        }
        return vehicles.first(where: \.isDefault)?.name
            ?? vehicles.first?.name
            ?? String(localized: "home.no.vehicle")
    }

    private func startTrip() {
        guard dependencies.subscriptions.canAccess(.startTrip) else {
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
