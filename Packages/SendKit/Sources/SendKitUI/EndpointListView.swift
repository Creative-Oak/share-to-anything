import SendKit
import SwiftUI

/// The main settings screen: endpoints and accounts in the sidebar, the editor as detail.
public struct EndpointListView: View {
    enum Item: Hashable {
        case endpoint(UUID)
    }

    @Environment(EndpointStore.self) private var store
    @State private var selection: Item?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Endpoints") {
                    ForEach(store.endpoints) { endpoint in
                        EndpointRow(endpoint: endpoint)
                            .tag(Item.endpoint(endpoint.id))
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete([endpoint.id]) }
                            }
                    }
                    .onDelete { offsets in delete(Set(offsets.map { store.endpoints[$0].id })) }
                    .onMove { store.move(from: $0, to: $1) }

                    if store.endpoints.isEmpty {
                        Text("Add an endpoint with +").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Share to Anything")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Dinero", systemImage: "doc.text.magnifyingglass") { add(.newDinero()) }
                        Button("Email", systemImage: "envelope") { add(.newEmail()) }
                        Button("HTTP", systemImage: "network") { add(.newHTTP()) }
                    } label: {
                        Label("Add Endpoint", systemImage: "plus")
                    }
                }
            }
        } detail: {
            switch selection {
            case .endpoint(let id):
                if let endpoint = store.endpoint(id: id) {
                    EndpointEditor(endpoint: endpoint).id(id)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(store.endpoints.isEmpty ? "No Endpoints" : "Select an Endpoint", systemImage: "paperplane")
        } description: {
            Text(store.endpoints.isEmpty
                 ? "Add a Dinero, email or HTTP endpoint, then send files to it from Finder or the share sheet."
                 : "Choose an endpoint in the sidebar to edit it.")
        } actions: {
            if store.endpoints.isEmpty {
                Menu("Add Endpoint") {
                    Button("Dinero", systemImage: "doc.text.magnifyingglass") { add(.newDinero()) }
                    Button("Email", systemImage: "envelope") { add(.newEmail()) }
                    Button("HTTP", systemImage: "network") { add(.newHTTP()) }
                }
                .fixedSize()
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func add(_ endpoint: Endpoint) {
        store.upsert(endpoint)
        selection = .endpoint(endpoint.id)
    }

    private func delete(_ ids: Set<UUID>) {
        if case .endpoint(let id) = selection, ids.contains(id) { selection = nil }
        store.delete(ids: ids)
    }
}

struct EndpointRow: View {
    var endpoint: Endpoint

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(endpoint.name)
                Text(endpoint.kindLabel).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: endpoint.symbol)
        }
    }
}
