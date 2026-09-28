import Foundation
import UniformTypeIdentifiers

/// A file on disk that is about to be sent.
public struct SharedFile: Hashable, Sendable {
    public var url: URL

    public init(url: URL) { self.url = url }

    public var filename: String { url.lastPathComponent }
    public var basename: String { url.deletingPathExtension().lastPathComponent }
    public var ext: String { url.pathExtension }

    public var mimeType: String {
        UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    public var size: Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    public func data() throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
