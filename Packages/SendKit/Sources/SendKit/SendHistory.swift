import Foundation

public struct SendRecord: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var endpointName: String
    public var files: [String]
    public var success: Bool
    public var message: String

    public init(endpointName: String, files: [String], success: Bool, message: String) {
        self.endpointName = endpointName
        self.files = files
        self.success = success
        self.message = message
    }
}

/// Recent sends, newest first, kept in the shared container.
public enum SendHistory {
    static let limit = 50
    static var fileURL: URL { AppConfig.containerURL.appending(path: "history.json") }

    public static func load() -> [SendRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SendRecord].self, from: data)) ?? []
    }

    public static func append(_ record: SendRecord) {
        let records = Array(([record] + load()).prefix(limit))
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
