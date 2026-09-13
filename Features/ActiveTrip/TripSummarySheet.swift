import CoreLocation
import MapKit
import SwiftUI
import SwiftData

/// What appears the instant STOP is pressed.
///
/// The figures are on screen before any classification is asked for, because the first
/// question after a drive is always "how far was that?". Business/Personal is two big
/// targets; everything below them is optional. Stopping here and pressing Business is a
/// complete, valid record.
struct TripSummarySheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let trip: Trip

    @State private var tripType: TripType?
    @State private var purpose: String = ""
    @State private var clientName: String = ""
    @State private var projectName: String = ""
    @State private var suggestion: FrequentLocation?
    @State private var showsDiscardConfirmation = false

    @Query(sort: \Client.lastUsedAt, order: .reverse) private var clients: [Client]
    @Query(sort: \Project.lastUsedAt, order: .reverse) private var projects: [Project]

    private var settings: UserSettings { dependencies.settingsStore.settings }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    routeMap
                    figures
                    classification
                    if tripType == .business {
                        suggestionBanner
                        purposeField
                        clientField
                        projectField
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "common.save") { save() }
                    .padding(20)
                    .background(.bar)
            }
            .navigationTitle("summary.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.discard", role: .destructive) { showsDiscardConfirmation = true }
                }
            }
        }
        .interactiveDismissDisabled()
        // Destructive, in the position where "Cancel" normally lives, and the only visible way
        // out of a sheet that cannot be swiped away: a reflex tap used to erase the drive that
        // was just recorded.
        .confirmationDialog("summary.discard.title", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
            Button("summary.discard.confirm", role: .destructive) { discard() }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("summary.discard.message")
        }
        .task { prepare() }
    }

    /// The drive itself, before any of the questions.
    ///
    /// It is also the only honest thing on this sheet when reverse geocoding failed: the
    /// addresses read "— → —", but the shape of the route is still recognisable and is what
    /// tells someone which trip they are about to classify.
    @ViewBuilder
    private var routeMap: some View {
        let route = decodedRoute
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
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel(Text("summary.route"))
        }
    }

    private var decodedRoute: [CLLocationCoordinate2D] {
        guard let data = trip.encodedRoute else { return [] }
        return RouteCompactor.decode(data).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
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
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.5)
            )
        )
    }

    private var figures: some View {
        VStack(spacing: 6) {
            MeterReadout(
                value: Fmt.distanceValue(meters: trip.distanceMeters, unit: settings.distanceUnit, locale: locale),
                unit: Fmt.unitAbbreviation(settings.distanceUnit, locale: locale),
                size: 62
            )
            if let amount = trip.calculatedAmount, let currency = trip.currencyCode, amount > 0 {
                Text(Fmt.money(amount, currencyCode: currency, locale: locale))
                    .scaledFont(22, relativeTo: .title2, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(verbatim: {
                let labels = dependencies.endpointLabels(for: trip)
                return "\(labels.start) → \(labels.end)"
            }())
                .scaledFont(14, relativeTo: .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    private var classification: some View {
        HStack(spacing: 12) {
            classificationButton(.business, systemImage: "briefcase.fill")
            classificationButton(.personal, systemImage: "house.fill")
        }
    }

    private func classificationButton(_ type: TripType, systemImage: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tripType = type }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage).scaledFont(22, relativeTo: .title2, weight: .semibold)
                Text(type == .business ? "trip.type.business" : "trip.type.personal")
                    .scaledFont(16, relativeTo: .body, weight: .semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .foregroundStyle(tripType == type ? .white : Theme.tint(for: type))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tripType == type ? Theme.tint(for: type) : Theme.tint(for: type).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tripType == type ? [.isSelected] : [])
    }

    @ViewBuilder
    private var suggestionBanner: some View {
        if let suggestion, let name = suggestionLabel(suggestion) {
            Button {
                clientName = name
                purpose = suggestion.purpose ?? purpose
                self.suggestion = nil
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(L.format("summary.suggestion", name))
                        .scaledFont(15, relativeTo: .subheadline, weight: .medium)
                    Spacer()
                    Text("summary.suggestion.apply").eyebrowStyle(Theme.signal)
                }
                .padding(14)
                .background(Theme.signal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var purposeField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("summary.purpose").eyebrowStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TripPurposePreset.allCases, id: \.self) { preset in
                        Button {
                            purpose = L.string("purpose.\(preset.rawValue)")
                        } label: {
                            Text(L.string("purpose.\(preset.rawValue)"))
                                .scaledFont(14, relativeTo: .subheadline, weight: .medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceRaised, in: Capsule())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("summary.purpose.placeholder", text: $purpose)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("summary.client").eyebrowStyle()
            TextField("summary.client.placeholder", text: $clientName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !clients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clients.prefix(8)) { client in
                            Button(client.name) { clientName = client.name }
                                .scaledFont(14, relativeTo: .subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceRaised, in: Capsule())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    /// Projects existed in the model and on the trip, and no screen in the app could ever
    /// set one. Same shape as the client field: type a name, or tap one already used.
    private var projectField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("summary.project").eyebrowStyle()
            TextField("summary.project.placeholder", text: $projectName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !projects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(projects.prefix(8)) { project in
                            Button(project.name) { projectName = project.name }
                                .scaledFont(14, relativeTo: .subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceRaised, in: Capsule())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func prepare() {
        tripType = settings.defaultTripType
        suggestion = dependencies.suggestedDestination(for: trip)
        if let suggestion {
            purpose = suggestion.purpose ?? ""
        }
    }

    private func suggestionLabel(_ location: FrequentLocation) -> String? {
        if let clientID = location.clientID,
           let client = clients.first(where: { $0.id == clientID }) {
            return client.name
        }
        return location.label
    }

    private func save() {
        trip.tripType = tripType ?? settings.defaultTripType
        trip.purpose = purpose.isEmpty ? nil : purpose
        if !clientName.isEmpty {
            trip.clientID = dependencies.client(named: clientName).id
        }
        if !projectName.isEmpty {
            trip.projectID = dependencies.project(named: projectName, clientID: trip.clientID).id
        }
        dependencies.finishTrip(trip)
        dismiss()
    }

    private func discard() {
        context.delete(trip)
        try? context.save()
        dependencies.clearFinishedTrip()
        dismiss()
    }
}
