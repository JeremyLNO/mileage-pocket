import SwiftUI
import SwiftData

/// Adding a drive that was not tracked — a forgotten trip, or one taken before the app was
/// installed. Everything the recorder would have produced, typed instead.
struct ManualTripView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var date = Date.now
    @State private var from = ""
    @State private var to = ""
    @State private var distanceText = ""
    @State private var tripType: TripType = .business
    @State private var purpose = ""
    @State private var clientName = ""
    @State private var vehicleID: UUID?

    private var settings: UserSettings { dependencies.settingsStore.settings }
    private var unit: DistanceUnit { settings.distanceUnit }

    private var distance: Double? {
        let normalized = distanceText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return unit.meters(fromValue: value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("manual.date", selection: $date, in: ...Date.now)
                    TextField("manual.from", text: $from)
                    TextField("manual.to", text: $to)
                    HStack {
                        TextField("manual.distance", text: $distanceText)
                            .keyboardType(.decimalPad)
                        Text(Fmt.unitAbbreviation(unit, locale: locale))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section {
                    Picker("manual.type", selection: $tripType) {
                        Text("trip.type.business").tag(TripType.business)
                        Text("trip.type.personal").tag(TripType.personal)
                    }
                    .pickerStyle(.segmented)

                    if !vehicles.isEmpty {
                        Picker("manual.vehicle", selection: $vehicleID) {
                            Text("manual.vehicle.none").tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(UUID?.some(vehicle.id))
                            }
                        }
                    }
                }

                if tripType == .business {
                    Section {
                        TextField("summary.purpose", text: $purpose)
                        TextField("summary.client", text: $clientName)
                    }
                }
            }
            .navigationTitle("manual.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(distance == nil)
                }
            }
            .task {
                tripType = settings.defaultTripType
                vehicleID = settings.defaultVehicleID ?? vehicles.first(where: \.isDefault)?.id
            }
        }
    }

    private func save() {
        guard let distance else { return }
        dependencies.createManualTrip(
            date: date,
            from: from,
            to: to,
            distanceMeters: distance,
            tripType: tripType,
            purpose: purpose,
            clientName: clientName,
            vehicleID: vehicleID
        )
        dismiss()
    }
}
