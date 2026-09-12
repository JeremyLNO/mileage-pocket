import SwiftUI
import SwiftData

struct VehiclesView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var editing: Vehicle?
    @State private var showsPaywall = false

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                Button {
                    editing = vehicle
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(vehicleSubtitle(vehicle))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if vehicle.isDefault {
                            Text("vehicles.default").eyebrowStyle(Theme.signal)
                        }
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("vehicles.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // The first vehicle is always free: a person with one car must be able
                    // to use the app they are evaluating.
                    if vehicles.isEmpty || dependencies.subscriptions.canAccess(.multipleVehicles) {
                        editing = dependencies.makeVehicle()
                    } else {
                        showsPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("vehicles.add"))
            }
        }
        .sheet(item: $editing) { vehicle in
            VehicleEditor(vehicle: vehicle)
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .overlay {
            if vehicles.isEmpty {
                EmptyStateView(
                    systemImage: "car.2",
                    title: "vehicles.empty.title",
                    message: "vehicles.empty.message"
                )
            }
        }
    }

    private func vehicleSubtitle(_ vehicle: Vehicle) -> String {
        [vehicle.registration, String(localized: String.LocalizationValue("vehicle.type.\(vehicle.vehicleTypeRaw)"))]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(vehicles[index])
        }
        try? context.save()
    }
}

/// Only the fields the selected country's rule actually uses are shown. Asking a German
/// driver for their fiscal horsepower is asking for a number their tax office never uses.
struct VehicleEditor: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var vehicle: Vehicle

    private var requiredPowerUnit: PowerUnit? {
        dependencies.requiredPowerUnit()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("vehicle.name", text: $vehicle.name)
                    Picker("vehicle.type", selection: $vehicle.vehicleTypeRaw) {
                        ForEach(VehicleType.allCases, id: \.rawValue) { type in
                            Text(LocalizedStringKey("vehicle.type.\(type.rawValue)")).tag(type.rawValue)
                        }
                    }
                    TextField("vehicle.registration", text: Binding(
                        get: { vehicle.registration ?? "" },
                        set: { vehicle.registration = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.characters)
                }

                if let requiredPowerUnit {
                    Section {
                        switch requiredPowerUnit {
                        case .fiscalHorsepower:
                            numberField("vehicle.fiscal.horsepower", value: $vehicle.fiscalHorsepower)
                        case .engineCapacity:
                            numberField("vehicle.engine.capacity", value: $vehicle.engineCapacity)
                        }
                    } footer: {
                        Text(requiredPowerUnit == .fiscalHorsepower ? "vehicle.fiscal.horsepower.help" : "vehicle.engine.capacity.help")
                    }
                }

                Section {
                    Toggle("vehicle.set.default", isOn: $vehicle.isDefault)
                }
            }
            .navigationTitle(vehicle.name.isEmpty ? String(localized: "vehicles.add") : vehicle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { save() }
                        .disabled(vehicle.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func numberField(_ label: LocalizedStringKey, value: Binding<Int?>) -> some View {
        TextField(label, value: value, format: .number)
            .keyboardType(.numberPad)
    }

    private func save() {
        dependencies.saveVehicle(vehicle)
        dismiss()
    }
}

/// Quick switcher shown from Home, so changing car before setting off is one tap and a tap.
struct VehiclePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Binding var selection: UUID?

    var body: some View {
        NavigationStack {
            List(vehicles) { vehicle in
                Button {
                    selection = vehicle.id
                    dismiss()
                } label: {
                    HStack {
                        Text(vehicle.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if vehicle.id == selection {
                            Image(systemName: "checkmark").foregroundStyle(Theme.signal)
                        }
                    }
                }
            }
            .navigationTitle("home.vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if vehicles.isEmpty {
                    EmptyStateView(systemImage: "car.2", title: "vehicles.empty.title", message: "vehicles.empty.message")
                }
            }
        }
    }
}
