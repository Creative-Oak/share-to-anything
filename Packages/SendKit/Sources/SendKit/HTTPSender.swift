import Foundation

struct HTTPSender {
    var endpoint: Endpoint
    var config: HTTPConfig
    var secrets: SecretStore
    var session: URLSession

    func send(_ file: SharedFile) async throws {
        let request = try makeRequest(for: file)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data, context: endpoint.name)
    }

    func makeRequest(for file: SharedFile, now: Date = Date()) throws -> URLRequest {
        let contents = try file.data()
        let template = Template(file: file, endpointName: endpoint.name, now: now,
                                extra: config.bodyMode == .json ? ["base64": contents.base64EncodedString()] : [:])

        let urlString = template.expand(config.url).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw SendError("\(endpoint.name): invalid URL “\(urlString)”.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = config.method.rawValue

        switch config.bodyMode {
        case .multipart:
            var body = MultipartBody()
            for field in config.formFields where !field.name.isEmpty {
                body.append(field: field.name, value: template.expand(field.value))
            }
            body.append(file: config.fileField.isEmpty ? "file" : config.fileField,
                        filename: file.filename, mimeType: file.mimeType, contents: contents)
            request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body.finalized()
        case .raw:
            request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = contents
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(template.expand(config.jsonTemplate).utf8)
        }

        // User headers go last so they can override Content-Type.
        for header in config.headers where !header.name.isEmpty {
            let value = header.isSecret
                ? secrets.get(header.secretKey(endpointID: endpoint.id)) ?? ""
                : template.expand(header.value)
            request.setValue(value, forHTTPHeaderField: header.name)
        }
        return request
    }

    static func check(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { throw SendError("\(context): no HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data.prefix(300), as: UTF8.self)
            throw SendError("\(context) returned HTTP \(http.statusCode). \(body)")
        }
    }
}
