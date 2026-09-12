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
    @State private var suggestion: FrequentLocation?

    @Query(sort: \Client.lastUsedAt, order: .reverse) private var clients: [Client]

    private var settings: UserSettings { dependencies.settingsStore.settings }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    figures
                    classification
                    if tripType == .business {
                        suggestionBanner
                        purposeField
                        clientField
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
                    Button("common.discard", role: .destructive) { discard() }
                }
            }
        }
        .interactiveDismissDisabled()
        .task { prepare() }
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
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("\(trip.startAddress ?? "—") → \(trip.endAddress ?? "—")")
                .font(.system(size: 14))
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
                Image(systemName: systemImage).font(.system(size: 22, weight: .semibold))
                Text(type == .business ? "trip.type.business" : "trip.type.personal")
                    .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 15, weight: .medium))
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
                            purpose = String(localized: String.LocalizationValue("purpose.\(preset.rawValue)"))
                        } label: {
                            Text(String(localized: String.LocalizationValue("purpose.\(preset.rawValue)")))
                                .font(.system(size: 14, weight: .medium))
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
                                .font(.system(size: 14))
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
