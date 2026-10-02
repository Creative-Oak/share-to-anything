import Foundation

/// Expands `{placeholder}` tokens in user-written templates.
///
/// Unknown placeholders are left untouched, so literal braces in JSON templates survive.
public struct Template {
    public static let placeholders = [
        "filename", "basename", "ext", "mime", "size", "date", "time", "datetime", "count", "endpoint",
    ]
    /// Only for HTTP endpoints: the endpoint's secret from the Keychain.
    public static let secretPlaceholder = "secret"

    public var values: [String: String]

    public init(values: [String: String]) { self.values = values }

    /// Context for a single file.
    public init(file: SharedFile, endpointName: String, now: Date = Date(), extra: [String: String] = [:]) {
        self.init(files: [file], endpointName: endpointName, now: now, extra: extra)
    }

    /// Context for a batch. Name-like values are joined with ", ".
    public init(files: [SharedFile], endpointName: String, now: Date = Date(), extra: [String: String] = [:]) {
        func join(_ key: (SharedFile) -> String) -> String { files.map(key).joined(separator: ", ") }
        var values: [String: String] = [
            "filename": join(\.filename),
            "basename": join(\.basename),
            "ext": join(\.ext),
            "mime": join(\.mimeType),
            "size": ByteCountFormatter.string(fromByteCount: Int64(files.reduce(0) { $0 + $1.size }), countStyle: .file),
            "date": Self.format(now, "yyyy-MM-dd"),
            "time": Self.format(now, "HH:mm"),
            "datetime": Self.format(now, "yyyy-MM-dd HH:mm"),
            "count": String(files.count),
            "endpoint": endpointName,
        ]
        values.merge(extra) { _, new in new }
        self.values = values
    }

    /// Expands a URL template, percent-encoding each value so file names can't break the URL.
    public func expandURL(_ template: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:")
        var encoded = self
        encoded.values = values.mapValues { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        return encoded.expand(template)
    }

    public func expand(_ template: String) -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            if let close = rest[afterOpen...].firstIndex(of: "}"),
               let value = values[String(rest[afterOpen..<close])] {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                result += "{"
                rest = rest[afterOpen...]
            }
        }
        return result + rest
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
