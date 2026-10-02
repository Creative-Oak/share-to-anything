import SendKit
import SwiftUI

/// The main settings screen: endpoints and accounts in the sidebar, the editor as detail.
public struct EndpointListView: View {
    enum Item: Hashable {
        case endpoint(UUID)
    }

    @Environment(EndpointStore.self) private var store
    @State private var selection: Item?
    @State private var isAdding = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Endpoints") {
                    ForEach(store.endpoints) { endpoint in
                        EndpointRow(endpoint: endpoint)
                            .tag(Item.endpoint(endpoint.id))
                            .contextMenu {
                                Button("Duplicate", systemImage: "plus.square.on.square") { add(endpoint.duplicate()) }
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
                    Button("Add Endpoint", systemImage: "plus") { isAdding = true }
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
        .sheet(isPresented: $isAdding) {
            PresetGallery { add($0) }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(store.endpoints.isEmpty ? "No Endpoints" : "Select an Endpoint", systemImage: "paperplane")
        } description: {
            Text(store.endpoints.isEmpty
                 ? "Pick a template such as Dinero, a folder, email or a webhook, then send files to it from Finder or the share sheet."
                 : "Choose an endpoint in the sidebar to edit it.")
        } actions: {
            if store.endpoints.isEmpty {
                Button("Add Endpoint") { isAdding = true }
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
