import Foundation

public struct DineroOrganization: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// Dinero echoes field names in whatever case they were requested, so match case-insensitively.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        func key(_ name: String) throws -> AnyKey {
            guard let key = container.allKeys.first(where: { $0.stringValue.lowercased() == name }) else {
                throw DecodingError.keyNotFound(AnyKey(stringValue: name), .init(codingPath: container.codingPath, debugDescription: "Missing \(name)"))
            }
            return key
        }
        id = try container.decode(Int.self, forKey: key("id"))
        name = try container.decodeIfPresent(String.self, forKey: key("name")) ?? "Organization \(id)"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encode(id, forKey: AnyKey(stringValue: "Id"))
        try container.encode(name, forKey: AnyKey(stringValue: "Name"))
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Dinero "Personlig integration": client ID/secret (per user) plus an API key (per organization)
/// are exchanged for a one-hour bearer token. There is no refresh token; we simply ask again.
///
/// Client credentials are shared by all Dinero endpoints; each endpoint stores its own API key.
public struct DineroAuth: Sendable {
    public static let tokenURL = URL(string: "https://authz.dinero.dk/dineroapi/oauth/token")!
    public static let apiBase = URL(string: "https://api.dinero.dk")!

    enum Key {
        static let clientID = "dinero.clientID"
        static let clientSecret = "dinero.clientSecret"
        static func apiKey(_ endpointID: UUID) -> String { "dinero.apiKey.\(endpointID)" }
    }

    var secrets: SecretStore
    var session: URLSession

    public init(secrets: SecretStore = .shared, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    // MARK: Credentials

    public var clientID: String {
        get { secrets.get(Key.clientID) ?? "" }
        nonmutating set { secrets.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: Key.clientID) }
    }

    public var clientSecret: String {
        get { secrets.get(Key.clientSecret) ?? "" }
        nonmutating set { secrets.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: Key.clientSecret) }
    }

    public var hasClientCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    public static func apiKeyKey(endpointID: UUID) -> String { Key.apiKey(endpointID) }

    public func apiKey(endpointID: UUID) -> String {
        secrets.get(Key.apiKey(endpointID))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Tokens

    /// Token cache lives in memory only; a token is cheap to get and valid for an hour.
    private static let cache = TokenCache()

    public func accessToken(apiKey: String) async throws -> String {
        guard hasClientCredentials else {
            throw SendError("Dinero client ID and secret are missing. Add them in the Dinero endpoint.")
        }
        guard !apiKey.isEmpty else {
            throw SendError("This Dinero endpoint has no API key.")
        }
        if let token = await Self.cache.token(for: apiKey) { return token }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("Basic \(Data("\(clientID):\(clientSecret)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode([
            "grant_type": "password",
            "scope": "read write",
            "username": apiKey,
            "password": apiKey,
        ]).utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, [400, 401].contains(http.statusCode) {
            throw SendError("Dinero rejected the credentials. Check the client ID, secret and API key.")
        }
        try HTTPSender.check(response, data: data, context: "Dinero login")
        struct TokenResponse: Decodable {
            var access_token: String
            var expires_in: Double?
        }
        let token = try Self.decode(TokenResponse.self, from: data, context: "Dinero login")
        await Self.cache.store(token.access_token, for: apiKey, lifetime: token.expires_in ?? 3600)
        return token.access_token
    }

    // MARK: API

    /// Organizations the API key can access (normally exactly one).
    public func organizations(apiKey: String) async throws -> [DineroOrganization] {
        let url = Self.apiBase.appending(path: "v1/organizations").appending(queryItems: [URLQueryItem(name: "fields", value: "Id,Name")])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken(apiKey: apiKey))", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try HTTPSender.check(response, data: data, context: "Dinero")
        return try Self.decode([DineroOrganization].self, from: data, context: "Dinero organizations")
    }

    // MARK: Helpers

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SendError("Unexpected reply from \(context): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}

actor TokenCache {
    private var tokens: [String: (token: String, expiry: Date)] = [:]

    func token(for key: String) -> String? {
        guard let entry = tokens[key], entry.expiry > Date() else { return nil }
        return entry.token
    }

    func store(_ token: String, for key: String, lifetime: TimeInterval) {
        tokens[key] = (token, Date().addingTimeInterval(lifetime - 60))
    }
}

struct DineroUploader {
    static let maxSize = 6 * 1024 * 1024
    static let allowedExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "bmp"]

    var endpointID: UUID
    var config: DineroConfig
    var auth: DineroAuth
    var session: URLSession

    func validate(_ file: SharedFile) throws {
        guard Self.allowedExtensions.contains(file.ext.lowercased()) else {
            throw SendError("Dinero only accepts PDFs and images — \(file.filename) is a .\(file.ext) file.")
        }
        guard file.size <= Self.maxSize else {
            throw SendError("\(file.filename) is larger than Dinero's 6 MB limit.")
        }
    }

    func upload(_ file: SharedFile) async throws {
        guard let organizationID = config.organizationID else {
            throw SendError("Choose a Dinero organization for this endpoint first.")
        }
        var body = MultipartBody()
        body.append(file: "file", filename: file.filename, mimeType: file.mimeType, contents: try file.data())

        let token = try await auth.accessToken(apiKey: auth.apiKey(endpointID: endpointID))
        var request = URLRequest(url: DineroAuth.apiBase.appending(path: "v1/\(organizationID)/files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.finalized()

        let (data, response) = try await session.data(for: request)
        try HTTPSender.check(response, data: data, context: "Dinero")
    }
}
