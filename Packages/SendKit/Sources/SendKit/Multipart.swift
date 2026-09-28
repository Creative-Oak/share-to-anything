import Foundation

/// Builds a multipart/form-data request body.
public struct MultipartBody {
    public let boundary: String
    private var data = Data()

    public init(boundary: String = "ShareToAnything-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func append(field name: String, value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"\r\n\r\n")
        data.append(value)
        data.append("\r\n")
    }

    public mutating func append(file name: String, filename: String, mimeType: String, contents: Data) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"; filename=\"\(Self.escape(filename))\"\r\n")
        data.append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(contents)
        data.append("\r\n")
    }

    public func finalized() -> Data {
        var result = data
        result.append("--\(boundary)--\r\n")
        return result
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}

extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
