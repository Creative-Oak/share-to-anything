import Foundation

/// A destination that files can be sent to.
public struct Endpoint: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown next to the endpoint in menus.
    public var symbol: String
    public var kind: Kind

    public enum Kind: Codable, Hashable, Sendable {
        case http(HTTPConfig)
        case email(EmailConfig)
        case dinero(DineroConfig)
    }

    public init(id: UUID = UUID(), name: String, symbol: String, kind: Kind) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
    }

    public var kindLabel: String {
        switch kind {
        case .http: "HTTP"
        case .email(let config): config.delivery == .draft ? "Email draft" : "Email (SMTP)"
        case .dinero: "Dinero"
        }
    }

    public static func newHTTP() -> Endpoint {
        Endpoint(name: "New HTTP endpoint", symbol: "network", kind: .http(HTTPConfig()))
    }

    public static func newEmail() -> Endpoint {
        Endpoint(name: "New email endpoint", symbol: "envelope", kind: .email(EmailConfig()))
    }

    public static func newDinero() -> Endpoint {
        Endpoint(name: "Dinero bilag", symbol: "doc.text.magnifyingglass", kind: .dinero(DineroConfig()))
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

    public init() {}
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
