import SwiftData
import SwiftUI

/// Corrects a recorded trip.
///
/// The detail screen could only ever edit the distance, which is the one field the GPS is
/// usually right about. Everything a person actually gets wrong — pressing START on the way
/// to the shops and only realising afterwards, driving the other car, the client's name —
/// was frozen the moment the summary sheet was dismissed.
///
/// Anything that changes the money reprices the trip through the same engine a recorded one
/// goes through, at the rule in force on the trip's own date — never today's.
struct TripEditor: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Project.name) private var projects: [Project]

    let trip: Trip

    @State private var tripType: TripType = .business
    @State private var purpose = ""
    @State private var vehicleID: UUID?
    @State private var clientID: UUID?
    @State private var projectID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section(L.string("detail.edit.classification")) {
                    Picker("manual.type", selection: $tripType) {
                        Text("trip.type.business").tag(TripType.business)
                        Text("trip.type.personal").tag(TripType.personal)
                    }
                    .pickerStyle(.segmented)
                }

                Section(L.string("detail.edit.details")) {
                    TextField("summary.purpose.placeholder", text: $purpose)

                    Picker("detail.vehicle", selection: $vehicleID) {
                        Text("manual.vehicle.none").tag(UUID?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.name).tag(UUID?.some(vehicle.id))
                        }
                    }

                    Picker("detail.client", selection: $clientID) {
                        Text("detail.client.none").tag(UUID?.none)
                        ForEach(clients) { client in
                            Text(client.name).tag(UUID?.some(client.id))
                        }
                    }

                    Picker("detail.project", selection: $projectID) {
                        Text("detail.project.none").tag(UUID?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }
                }

                Section {
                    Text("detail.edit.note")
                        .scaledFont(13, relativeTo: .footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("detail.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        tripType = trip.tripType
        purpose = trip.purpose ?? ""
        vehicleID = trip.vehicleID
        clientID = trip.clientID
        projectID = trip.projectID
    }

    private func save() {
        trip.tripType = tripType
        trip.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines).ifEmptyNil()
        trip.vehicleID = vehicleID
        trip.clientID = clientID
        trip.projectID = projectID
        dependencies.repriceEditedTrip(trip)
        dismiss()
    }
}

private extension String {
    func ifEmptyNil() -> String? { isEmpty ? nil : self }
}
