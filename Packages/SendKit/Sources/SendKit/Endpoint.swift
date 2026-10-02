import Foundation

/// A destination that files can be sent to.
public struct Endpoint: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown next to the endpoint in menus.
    public var symbol: String
    public var kind: Kind
    /// Setup help shown at the top of the editor; filled in by presets.
    public var hint: String = ""
    /// Comma-separated extensions this endpoint is offered for. Empty means every file.
    public var fileTypes: String = ""
    public var prepare = Preparation()
    public var afterSend = AfterSend()

    public enum Kind: Codable, Hashable, Sendable {
        case http(HTTPConfig)
        case email(EmailConfig)
        case dinero(DineroConfig)
        case folder(FolderConfig)
    }

    public init(id: UUID = UUID(), name: String, symbol: String, kind: Kind, hint: String = "", fileTypes: String = "") {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.hint = hint
        self.fileTypes = fileTypes
    }

    // Fields added after 1.0 are optional on disk so older data keeps loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        kind = try container.decode(Kind.self, forKey: .kind)
        hint = try container.decodeIfPresent(String.self, forKey: .hint) ?? ""
        fileTypes = try container.decodeIfPresent(String.self, forKey: .fileTypes) ?? ""
        prepare = try container.decodeIfPresent(Preparation.self, forKey: .prepare) ?? Preparation()
        afterSend = try container.decodeIfPresent(AfterSend.self, forKey: .afterSend) ?? AfterSend()
    }

    public var kindLabel: String {
        switch kind {
        case .http: "HTTP"
        case .email(let config): config.delivery == .draft ? "Email draft" : "Email (SMTP)"
        case .dinero: "Dinero"
        case .folder(let config): config.move ? "Move to folder" : "Copy to folder"
        }
    }

    /// Keychain account for the endpoint's `{secret}` placeholder value.
    public var secretKey: String { "secret.\(id)" }

    // MARK: File type filter

    static let dineroExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp"]

    /// Lowercased extensions this endpoint accepts, or nil for any file.
    public var acceptedExtensions: Set<String>? {
        let custom = Set(fileTypes.lowercased()
            .split(whereSeparator: { ", ;".contains($0) })
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : String($0) }
            .filter { !$0.isEmpty })
        if case .dinero = kind { return custom.isEmpty ? Self.dineroExtensions : custom.intersection(Self.dineroExtensions) }
        return custom.isEmpty ? nil : custom
    }

    public func accepts(_ url: URL) -> Bool {
        guard let accepted = acceptedExtensions else { return true }
        return accepted.contains(url.pathExtension.lowercased())
    }

    /// Whether the endpoint should be offered for this selection on this device.
    public func isOffered(for urls: [URL]) -> Bool {
        #if !os(macOS)
        if case .folder = kind { return false }
        #endif
        return urls.allSatisfy(accepts)
    }

    public static func newHTTP() -> Endpoint {
        Endpoint(name: "New HTTP endpoint", symbol: "network", kind: .http(HTTPConfig()))
    }

    public static func newEmail() -> Endpoint {
        Endpoint(name: "New email endpoint", symbol: "envelope", kind: .email(EmailConfig()))
    }

    public static func newDinero() -> Endpoint {
        var endpoint = Endpoint(name: "Dinero bilag", symbol: "doc.text.magnifyingglass", kind: .dinero(DineroConfig()))
        endpoint.prepare.imageFormat = .jpeg
        return endpoint
    }

    public static func newFolder() -> Endpoint {
        Endpoint(name: "Copy to folder", symbol: "folder", kind: .folder(FolderConfig()))
    }
}

// MARK: - Preparation and follow-up

/// Changes made to files before they are sent. Originals are never modified.
public struct Preparation: Codable, Hashable, Sendable {
    public enum ImageFormat: String, Codable, CaseIterable, Sendable {
        case original, jpeg, pdf
        public var label: String {
            switch self {
            case .original: "Keep original"
            case .jpeg: "Convert to JPEG"
            case .pdf: "Convert to PDF"
            }
        }
    }

    public var imageFormat: ImageFormat = .original
    /// Images above this size are scaled down and recompressed. 0 turns this off.
    public var maxSizeMB: Double = 0
    /// Template for the sent file's name, e.g. `{date} {basename}.{ext}`. Empty keeps the name.
    public var rename: String = ""

    public init() {}

    public var isActive: Bool { imageFormat != .original || maxSizeMB > 0 || !rename.isEmpty }
}

/// What happens to the original file once it was sent successfully (macOS).
public struct AfterSend: Codable, Hashable, Sendable {
    /// Finder tag to add, e.g. "Sent to Dinero". Empty adds none.
    public var tag: String = ""
    /// Folder to move the original into. Empty leaves it where it is.
    public var moveTo: String = ""

    public init() {}

    public var isActive: Bool { !tag.isEmpty || !moveTo.isEmpty }
}

public struct FolderConfig: Codable, Hashable, Sendable {
    public var path: String = ""
    /// Move the file instead of copying it.
    public var move: Bool = false

    public init(path: String = "", move: Bool = false) {
        self.path = path
        self.move = move
    }
}

// MARK: - HTTP

public struct HTTPConfig: Codable, Hashable, Sendable {
    public enum Method: String, Codable, CaseIterable, Sendable { case POST, PUT, PATCH }

    public enum BodyMode: String, Codable, CaseIterable, Sendable {
        /// multipart/form-data with the file under `fileField` plus extra `formFields`.
        case multipart
        /// The raw file bytes, Content-Type set to the file's MIME type.
        case raw
        /// `jsonTemplate` with placeholders expanded, including `{base64}`.
        case json

        public var label: String {
            switch self {
            case .multipart: "Multipart form"
            case .raw: "Raw file"
            case .json: "JSON (base64)"
            }
        }
    }

    public var url: String = "https://"
    public var method: Method = .POST
    public var headers: [Header] = []
    public var bodyMode: BodyMode = .multipart
    public var fileField: String = "file"
    public var formFields: [FormField] = []
    public var jsonTemplate: String = #"{"filename": "{filename}", "data": "{base64}"}"#
    /// When set, sends HTTP Basic auth with this username and the endpoint's `{secret}` as password.
    public var username: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decode(Method.self, forKey: .method)
        headers = try container.decodeIfPresent([Header].self, forKey: .headers) ?? []
        bodyMode = try container.decode(BodyMode.self, forKey: .bodyMode)
        fileField = try container.decodeIfPresent(String.self, forKey: .fileField) ?? "file"
        formFields = try container.decodeIfPresent([FormField].self, forKey: .formFields) ?? []
        jsonTemplate = try container.decodeIfPresent(String.self, forKey: .jsonTemplate) ?? HTTPConfig().jsonTemplate
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
    }
}

public struct Header: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    /// Template for non-secret headers. Ignored when `isSecret` — the value lives in the Keychain.
    public var value: String
    public var isSecret: Bool

    public init(name: String = "", value: String = "", isSecret: Bool = false) {
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }

    /// Keychain account under which a secret header's value is stored.
    public func secretKey(endpointID: UUID) -> String { "header.\(endpointID).\(id)" }
}

public struct FormField: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String

    public init(name: String = "", value: String = "") {
        self.name = name
        self.value = value
    }
}

// MARK: - Email

public struct EmailConfig: Codable, Hashable, Sendable {
    public enum Delivery: String, Codable, CaseIterable, Sendable {
        case draft, smtp
        public var label: String { self == .draft ? "Review in mail app" : "Send immediately (SMTP)" }
    }

    public var to: String = ""
    public var cc: String = ""
    public var bcc: String = ""
    public var subject: String = "{filename}"
    public var body: String = "Sent from Share to Anything on {date}."
    public var delivery: Delivery = .draft
    public var smtp: SMTPConfig = SMTPConfig()

    public init() {}

    public var toList: [String] { Self.split(to) }
    public var ccList: [String] { Self.split(cc) }
    public var bccList: [String] { Self.split(bcc) }

    static func split(_ list: String) -> [String] {
        list.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

public struct SMTPConfig: Codable, Hashable, Sendable {
    public enum Security: String, Codable, CaseIterable, Sendable {
        /// Implicit TLS, usually port 465.
        case tls
        /// Plain connection upgraded with STARTTLS, usually port 587.
        case startTLS

        public var label: String { self == .tls ? "TLS (465)" : "STARTTLS (587)" }
        public var defaultPort: Int { self == .tls ? 465 : 587 }
    }

    public var host: String = ""
    public var port: Int = 587
    public var security: Security = .startTLS
    public var username: String = ""
    public var fromAddress: String = ""
    public var fromName: String = ""

    public init() {}

    public static func passwordKey(endpointID: UUID) -> String { "smtp.\(endpointID)" }
}

// MARK: - Dinero

public struct DineroConfig: Codable, Hashable, Sendable {
    public var organizationID: Int?
    public var organizationName: String = ""

    public init(organizationID: Int? = nil, organizationName: String = "") {
        self.organizationID = organizationID
        self.organizationName = organizationName
    }
}
