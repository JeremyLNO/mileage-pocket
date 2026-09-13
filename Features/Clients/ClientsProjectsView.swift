import SwiftData
import SwiftUI

/// Where the names typed on a trip can be corrected.
///
/// Clients used to be created implicitly — type a name on a trip summary and one appears —
/// and then be unreachable forever: a typo became a second client on every report, with no
/// way to rename or remove it. Projects were worse: the model existed, the trip carried a
/// `projectID`, and nothing in the app could ever set one.
///
/// Deleting detaches rather than cascades. The drive happened; a tidied-up name must never
/// cost the record of it.
struct ClientsProjectsView: View {
    @Environment(AppDependencies.self) private var dependencies

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var editingClient: Client?
    @State private var editingProject: Project?
    @State private var pendingClientDeletion: Client?
    @State private var pendingProjectDeletion: Project?

    var body: some View {
        List {
            Section(L.string("clients.section")) {
                ForEach(clients) { client in
                    Button {
                        editingClient = client
                    } label: {
                        row(
                            title: client.name,
                            subtitle: L.format("clients.trip.count", dependencies.tripCount(forClient: client.id))
                        )
                    }
                    .swipeActions {
                        Button(L.string("common.delete"), role: .destructive) {
                            pendingClientDeletion = client
                        }
                    }
                }
                Button(L.string("clients.add")) {
                    editingClient = Client(name: "")
                }
                .foregroundStyle(Theme.signal)
            }

            Section(L.string("projects.section")) {
                ForEach(projects) { project in
                    Button {
                        editingProject = project
                    } label: {
                        row(
                            title: project.name,
                            subtitle: project.clientID.flatMap { dependencies.clientName(for: $0) }
                                ?? L.string("project.client.none")
                        )
                    }
                    .swipeActions {
                        Button(L.string("common.delete"), role: .destructive) {
                            pendingProjectDeletion = project
                        }
                    }
                }
                Button(L.string("projects.add")) {
                    editingProject = Project(name: "")
                }
                .foregroundStyle(Theme.signal)
            }
        }
        .navigationTitle("clients.title")
        .overlay {
            if clients.isEmpty && projects.isEmpty {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "clients.empty.title",
                    message: "clients.empty.message"
                )
            }
        }
        .sheet(item: $editingClient) { client in
            ClientEditor(client: client)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditor(project: project)
        }
        .confirmationDialog(
            L.string("detail.delete.title"),
            isPresented: Binding(
                get: { pendingClientDeletion != nil },
                set: { if !$0 { pendingClientDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L.string("common.delete"), role: .destructive) {
                if let client = pendingClientDeletion { dependencies.deleteClient(client) }
                pendingClientDeletion = nil
            }
            Button(L.string("common.cancel"), role: .cancel) { pendingClientDeletion = nil }
        } message: {
            Text(L.string("clients.delete.message"))
        }
        .confirmationDialog(
            L.string("detail.delete.title"),
            isPresented: Binding(
                get: { pendingProjectDeletion != nil },
                set: { if !$0 { pendingProjectDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L.string("common.delete"), role: .destructive) {
                if let project = pendingProjectDeletion { dependencies.deleteProject(project) }
                pendingProjectDeletion = nil
            }
            Button(L.string("common.cancel"), role: .cancel) { pendingProjectDeletion = nil }
        } message: {
            Text(L.string("clients.delete.message"))
        }
    }

    private func row(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.isEmpty ? "—" : title)
                .scaledFont(16, relativeTo: .body, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .scaledFont(13, relativeTo: .footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Same pattern as the vehicle editor: nothing is inserted until Done, so abandoning the
/// sheet leaves no nameless row behind.
private struct ClientEditor: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var client: Client

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.string("client.name"), text: $client.name)
            }
            .navigationTitle(L.string("clients.section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.string("common.done")) { save() }
                        .disabled(client.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        client.name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if client.modelContext == nil { context.insert(client) }
        try? context.save()
        dependencies.invalidate()
        dismiss()
    }
}

private struct ProjectEditor: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Client.name) private var clients: [Client]
    @Bindable var project: Project

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.string("project.name"), text: $project.name)
                Picker(L.string("project.client"), selection: $project.clientID) {
                    Text(L.string("project.client.none")).tag(UUID?.none)
                    ForEach(clients) { client in
                        Text(client.name).tag(UUID?.some(client.id))
                    }
                }
            }
            .navigationTitle(L.string("projects.section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.string("common.done")) { save() }
                        .disabled(project.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if project.modelContext == nil { context.insert(project) }
        try? context.save()
        dependencies.invalidate()
        dismiss()
    }
}
