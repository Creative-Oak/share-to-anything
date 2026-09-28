import Foundation

struct SMTPReply: Equatable {
    var code: Int
    var lines: [String]

    var text: String { lines.joined(separator: " ") }

    /// Consumes one complete (possibly multi-line) reply from `buffer`, or returns nil if more data is needed.
    static func parse(from buffer: inout Data) -> SMTPReply? {
        var lines: [String] = []
        var cursor = buffer.startIndex
        while let lineEnd = buffer[cursor...].firstRange(of: Data("\r\n".utf8)) {
            let line = String(decoding: buffer[cursor..<lineEnd.lowerBound], as: UTF8.self)
            cursor = lineEnd.upperBound
            guard line.count >= 3, let code = Int(line.prefix(3)) else { continue }
            let separator = line.dropFirst(3).first
            lines.append(String(line.dropFirst(4)))
            if separator != "-" {
                buffer.removeSubrange(buffer.startIndex..<cursor)
                return SMTPReply(code: code, lines: lines)
            }
        }
        return nil
    }
}

/// Minimal SMTP submission client (TLS or STARTTLS, AUTH PLAIN/LOGIN).
struct SMTPSender {
    var config: SMTPConfig
    var password: String
    var session: URLSession

    func send(_ draft: MailDraft) async throws {
        do {
            try await deliver(draft)
        } catch let error as SendError {
            throw error
        } catch {
            throw Self.explain(error, host: Self.hostName(config.host), port: config.port)
        }
    }

    /// Accepts what people paste: "smtp://host:587/", " host ", etc.
    static func hostName(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = host.range(of: "://") { host = String(host[range.upperBound...]) }
        host = String(host.prefix { $0 != "/" })
        if let colon = host.lastIndex(of: ":"), Int(host[host.index(after: colon)...]) != nil {
            host = String(host[..<colon])
        }
        return host
    }

    /// Turns CFNetwork/URL errors into something actionable.
    static func explain(_ error: Error, host: String, port: Int) -> SendError {
        let nsError = error as NSError
        let cfNetwork = kCFErrorDomainCFNetwork as String
        switch (nsError.domain, nsError.code) {
        case (cfNetwork, 1), (cfNetwork, 2),
             (NSURLErrorDomain, NSURLErrorCannotFindHost), (NSURLErrorDomain, NSURLErrorDNSLookupFailed):
            return SendError("Couldn't find the SMTP server “\(host)”. Check the Server field.")
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            return SendError("Timed out connecting to \(host):\(port). Check the server, port and security setting.")
        case (NSURLErrorDomain, NSURLErrorCannotConnectToHost):
            return SendError("\(host) refused the connection on port \(port).")
        case (NSURLErrorDomain, NSURLErrorSecureConnectionFailed), (NSOSStatusErrorDomain, _):
            return SendError("Secure connection to \(host):\(port) failed. Try the other security option (TLS 465 / STARTTLS 587).")
        default:
            return SendError("SMTP: \(error.localizedDescription)")
        }
    }

    private func deliver(_ draft: MailDraft) async throws {
        let host = Self.hostName(config.host)
        guard !host.isEmpty else { throw SendError("SMTP server is not configured.") }
        guard !host.contains("@") else {
            throw SendError("The SMTP server should be a host name like smtp.gmail.com, not an email address.")
        }
        let from = config.fromAddress.isEmpty ? config.username : config.fromAddress
        guard !from.isEmpty else { throw SendError("SMTP sender address is not configured.") }

        let message = MIMEMessage(
            fromAddress: from, fromName: config.fromName, to: draft.to, cc: draft.cc,
            subject: draft.subject, body: draft.body,
            attachments: try draft.attachments.map { .init(filename: $0.filename, mimeType: $0.mimeType, data: try $0.data()) }
        )

        let connection = SMTPConnection(task: session.streamTask(withHostName: host, port: config.port))
        defer { connection.close() }
        try await connection.open(implicitTLS: config.security == .tls)
        var capabilities = try await connection.ehlo()

        if config.security == .startTLS {
            guard capabilities.contains(where: { $0.uppercased().hasPrefix("STARTTLS") }) else {
                throw SendError("\(host) does not offer STARTTLS. Try TLS on port 465.")
            }
            try await connection.command("STARTTLS", expect: 220)
            connection.startTLS()
            capabilities = try await connection.ehlo()
        }

        if !config.username.isEmpty {
            let auth = capabilities.first { $0.uppercased().hasPrefix("AUTH") }?.uppercased() ?? ""
            if auth.contains("PLAIN") || !auth.contains("LOGIN") {
                let token = Data("\0\(config.username)\0\(password)".utf8).base64EncodedString()
                try await connection.command("AUTH PLAIN \(token)", expect: 235, redact: true)
            } else {
                try await connection.command("AUTH LOGIN", expect: 334)
                try await connection.command(Data(config.username.utf8).base64EncodedString(), expect: 334, redact: true)
                try await connection.command(Data(password.utf8).base64EncodedString(), expect: 235, redact: true)
            }
        }

        try await connection.command("MAIL FROM:<\(from)>", expect: 250)
        for recipient in draft.to + draft.cc + draft.bcc {
            try await connection.command("RCPT TO:<\(recipient)>", expect: 250, 251)
        }
        try await connection.command("DATA", expect: 354)
        try await connection.writeData(Self.dotStuffed(message.render()))
        try await connection.expect(250)
        _ = try? await connection.command("QUIT", expect: 221)
    }

    /// Escapes lines starting with "." and appends the terminating "\r\n.\r\n".
    static func dotStuffed(_ data: Data) -> Data {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix(".") { text = "." + text }
        text = text.replacingOccurrences(of: "\r\n.", with: "\r\n..")
        if !text.hasSuffix("\r\n") { text += "\r\n" }
        return Data((text + ".\r\n").utf8)
    }
}

final class SMTPConnection: @unchecked Sendable {
    private let task: URLSessionStreamTask
    private var buffer = Data()
    private let timeout: TimeInterval = 30

    init(task: URLSessionStreamTask) { self.task = task }

    func open(implicitTLS: Bool) async throws {
        task.resume()
        if implicitTLS { task.startSecureConnection() }
        try await expect(220)
    }

    func startTLS() {
        buffer.removeAll()
        task.startSecureConnection()
    }

    func close() { task.cancel() }

    /// Sends EHLO and returns the advertised extensions.
    func ehlo() async throws -> [String] {
        let reply = try await command("EHLO sharetoanything.local", expect: 250)
        return Array(reply.lines.dropFirst())
    }

    @discardableResult
    func command(_ line: String, expect codes: Int..., redact: Bool = false) async throws -> SMTPReply {
        try await writeData(Data((line + "\r\n").utf8))
        return try await expect(codes, after: redact ? String(line.prefix(10)) + "…" : line)
    }

    func writeData(_ data: Data) async throws {
        try await task.write(data, timeout: timeout)
    }

    @discardableResult
    func expect(_ codes: Int...) async throws -> SMTPReply {
        try await expect(codes, after: nil)
    }

    private func expect(_ codes: [Int], after command: String?) async throws -> SMTPReply {
        let reply = try await readReply()
        guard codes.contains(reply.code) else {
            let context = command.map { " after \($0.components(separatedBy: " ").first ?? $0)" } ?? ""
            throw SendError("SMTP error\(context): \(reply.code) \(reply.text)")
        }
        return reply
    }

    private func readReply() async throws -> SMTPReply {
        while true {
            if let reply = SMTPReply.parse(from: &buffer) { return reply }
            let (data, atEOF) = try await task.readData(ofMinLength: 1, maxLength: 65536, timeout: timeout)
            if let data { buffer.append(data) }
            if atEOF && (data?.isEmpty ?? true) { throw SendError("SMTP server closed the connection.") }
        }
    }
}
