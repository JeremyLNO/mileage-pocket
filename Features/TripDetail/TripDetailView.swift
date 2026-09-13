import MapKit
import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    @State private var showsEditor = false
    @State private var showsDistanceEditor = false
    @State private var showsRecalculateConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsPaywall = false
    @State private var editedDistance = ""

    private var unit: DistanceUnit { dependencies.settingsStore.settings.distanceUnit }

    private var route: [CLLocationCoordinate2D] {
        guard let data = trip.encodedRoute else { return [] }
        return RouteCompactor.decode(data).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                mapCard
                headline
                detailsCard
                calculationCard
                actions
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle(trip.startedAt.formatted(.dateTime.day().month(.abbreviated).year()))
        .navigationBarTitleDisplayMode(.inline)
        .alert("detail.edit.distance", isPresented: $showsDistanceEditor) {
            TextField("detail.edit.distance", text: $editedDistance)
                .keyboardType(.decimalPad)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") { applyDistanceEdit() }
        } message: {
            Text("detail.edit.distance.message")
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .sheet(isPresented: $showsEditor) { TripEditor(trip: trip) }
        // Deleting was the one destructive action with no confirmation, while recalculating —
        // which is reversible — had one.
        .confirmationDialog("detail.delete.title", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                dependencies.delete(trip)
                dismiss()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("detail.delete.message")
        }
        .confirmationDialog("detail.recalculate", isPresented: $showsRecalculateConfirmation, titleVisibility: .visible) {
            Button("detail.recalculate.confirm") { dependencies.recalculate(trip) }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("detail.recalculate.message")
        }
    }

    @ViewBuilder
    private var mapCard: some View {
        if route.count > 1 {
            Map(initialPosition: .region(region(for: route))) {
                MapPolyline(coordinates: route)
                    .stroke(Theme.signal, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let first = route.first {
                    Marker("detail.start", systemImage: "flag.fill", coordinate: first).tint(Theme.business)
                }
                if let last = route.last {
                    Marker("detail.end", systemImage: "flag.checkered", coordinate: last).tint(Theme.signal)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            MeterReadout(
                value: Fmt.distanceValue(meters: trip.distanceMeters, unit: unit, locale: locale),
                unit: Fmt.unitAbbreviation(unit, locale: locale),
                size: 56
            )
            if let amount = trip.calculatedAmount, let currency = trip.currencyCode {
                Text(Fmt.money(amount, currencyCode: currency, locale: locale))
                    .scaledFont(20, relativeTo: .title3, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            TripTypePill(type: trip.tripType)
            if trip.isManuallyEdited {
                Label("detail.edited", systemImage: "pencil")
                    .eyebrowStyle(Theme.signal)
            }
            if trip.unbridgedGapSeconds > 0 {
                gapNotice
            }
        }
    }

    /// A stretch the receiver went quiet for and the filter refused to invent across. The
    /// distance really is short, and the driver is the only one who can say by how much.
    private var gapNotice: some View {
        Label(
            L.format("trip.gap.notice", Fmt.duration(trip.unbridgedGapSeconds, locale: locale)),
            systemImage: "antenna.radiowaves.left.and.right.slash"
        )
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var detailsCard: some View {
        Card {
            VStack(spacing: 0) {
                row("detail.from", fullAddress(street: trip.startStreet, town: trip.startAddress))
                row("detail.to", fullAddress(street: trip.endStreet, town: trip.endAddress))
                row("detail.departure", trip.startedAt.formatted(date: .omitted, time: .shortened))
                row("detail.arrival", trip.endedAt?.formatted(date: .omitted, time: .shortened) ?? "—")
                row("detail.duration", Fmt.duration(trip.duration, locale: locale))
                row("detail.vehicle", dependencies.vehicleName(for: trip.vehicleID) ?? "—")
                if let purpose = trip.purpose, !purpose.isEmpty {
                    row("detail.purpose", purpose)
                }
                if let clientID = trip.clientID, let name = dependencies.clientName(for: clientID) {
                    row("detail.client", name)
                }
                if let projectID = trip.projectID, let name = dependencies.projectName(for: projectID) {
                    row("detail.project", name)
                }
            }
        }
    }

    private var calculationCard: some View {
        Card {
            VStack(spacing: 0) {
                row("detail.country", CountryCatalog.info(for: trip.countryCode, locale: locale)?.name ?? trip.countryCode)
                if let rate = trip.mileageRate, let currency = trip.currencyCode {
                    row("detail.rate", Fmt.rate(rate, currencyCode: currency, unit: unit, locale: locale))
                }
                row("detail.rule", trip.isOfficialRate ? L.string("rate.official") : L.string("rate.custom"))
                if let version = trip.mileageRuleVersion {
                    row("detail.rule.version", version)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            SecondaryButton(title: "detail.edit") { showsEditor = true }
            SecondaryButton(title: "detail.edit.distance") {
                editedDistance = Fmt.distanceValue(meters: trip.distanceMeters, unit: unit, locale: Locale(identifier: "en_US_POSIX"))
                showsDistanceEditor = true
            }
            SecondaryButton(title: "detail.recalculate") { showsRecalculateConfirmation = true }
            SecondaryButton(title: "detail.duplicate") {
                // A duplicate is a new trip. Leaving it ungated made "record trips" free for
                // anyone willing to press it twice.
                guard dependencies.canAccess(.manualTrip) else {
                    showsPaywall = true
                    return
                }
                dependencies.duplicate(trip)
                dismiss()
            }
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Text("common.delete")
                    .scaledFont(16, relativeTo: .body, weight: .medium)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
    }

    /// The detail screen has the room, and it is where someone checks exactly where they
    /// went — so both levels are shown here, unlike the list rows.
    private func fullAddress(street: String?, town: String?) -> String {
        [street, town].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            .ifEmpty("—")
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(14, relativeTo: .subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .scaledFont(15, relativeTo: .subheadline, weight: .medium)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max()
        else { return MKCoordinateRegion() }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.005, (maxLon - minLon) * 1.4)
            )
        )
    }

    private func applyDistanceEdit() {
        guard let value = Double(editedDistance.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
        trip.correctedDistanceMeters = unit.meters(fromValue: value)
        trip.isManuallyEdited = true
        trip.updatedAt = .now
        // The amount follows the corrected distance, but under the rule already frozen on
        // this trip — never under today's scale.
        dependencies.recalculateWithFrozenRule(trip)
    }
}
