import Foundation
import Observation

struct EndpointList: Codable {
    var endpoints: [Endpoint]
    var modified: Date

    init(endpoints: [Endpoint], modified: Date) {
        self.endpoints = endpoints
        self.modified = modified
    }

    /// Skips endpoints this version can't read (e.g. a kind added by a newer version on another device).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modified = try container.decode(Date.self, forKey: .modified)
        endpoints = try container.decode([Lossy].self, forKey: .endpoints).compactMap(\.endpoint)
    }

    private struct Lossy: Decodable {
        var endpoint: Endpoint?
        init(from decoder: Decoder) throws { endpoint = try? Endpoint(from: decoder) }
    }
}

/// The endpoint list, persisted in the shared container and (in the main app) synced through iCloud KVS.
///
/// Extensions only read: use `EndpointStore.load()`.
@MainActor
@Observable
public final class EndpointStore {
    public private(set) var endpoints: [Endpoint]
    private var modified: Date

    @ObservationIgnored private let syncsWithICloud: Bool
    @ObservationIgnored private var observer: NSObjectProtocol?

    nonisolated static let kvsKey = "endpoints"
    nonisolated static var fileURL: URL { AppConfig.containerURL.appending(path: "endpoints.json") }

    /// Reads the current endpoint list from disk without any syncing.
    public nonisolated static func load() -> [Endpoint] {
        readFile()?.endpoints ?? []
    }

    nonisolated static func readFile() -> EndpointList? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(EndpointList.self, from: data)
    }

    public init(syncsWithICloud: Bool) {
        let local = Self.readFile()
        endpoints = local?.endpoints ?? []
        modified = local?.modified ?? .distantPast
        self.syncsWithICloud = syncsWithICloud
        guard syncsWithICloud else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromICloud() }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
        pullFromICloud()
    }

    public func endpoint(id: UUID) -> Endpoint? {
        endpoints.first { $0.id == id }
    }

    public func upsert(_ endpoint: Endpoint) {
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
        } else {
            endpoints.append(endpoint)
        }
        save()
    }

    public func delete(ids: Set<UUID>) {
        endpoints.removeAll { ids.contains($0.id) }
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        let moving = source.map { endpoints[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.reversed() { endpoints.remove(at: index) }
        endpoints.insert(contentsOf: moving, at: insertAt)
        save()
    }

    /// Re-reads the file, e.g. after another process changed it.
    public func reload() {
        guard let local = Self.readFile(), local.modified > modified else { return }
        endpoints = local.endpoints
        modified = local.modified
    }

    private func save() {
        modified = Date()
        let list = EndpointList(endpoints: endpoints, modified: modified)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        if syncsWithICloud {
            NSUbiquitousKeyValueStore.default.set(data, forKey: Self.kvsKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Last writer wins, compared on the list's modification date.
    private func pullFromICloud() {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.kvsKey),
              let remote = try? JSONDecoder().decode(EndpointList.self, from: data) else {
            // Nothing in iCloud yet: seed it with what we have.
            if !endpoints.isEmpty, let data = try? JSONEncoder().encode(EndpointList(endpoints: endpoints, modified: modified)) {
                NSUbiquitousKeyValueStore.default.set(data, forKey: Self.kvsKey)
            }
            return
        }
        guard remote.modified > modified else { return }
        endpoints = remote.endpoints
        modified = remote.modified
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
