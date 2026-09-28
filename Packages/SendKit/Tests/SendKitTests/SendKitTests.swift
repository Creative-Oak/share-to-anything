import Foundation
import Testing
@testable import SendKit

private func tempFile(_ name: String, _ contents: String = "hello") throws -> SharedFile {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: name)
    try Data(contents.utf8).write(to: url)
    return SharedFile(url: url)
}

@Suite struct TemplateTests {
    @Test func expandsKnownPlaceholders() throws {
        let file = try tempFile("Kvittering Netto.pdf")
        let date = ISO8601DateFormatter().date(from: "2026-09-28T10:15:00Z")!
        var template = Template(file: file, endpointName: "Dinero", now: date)
        template.values["time"] = "12:15"
        #expect(template.expand("Bilag: {filename} ({ext}) {date} {time} via {endpoint}")
                == "Bilag: Kvittering Netto.pdf (pdf) 2026-09-28 12:15 via Dinero")
        #expect(template.expand("{mime}") == "application/pdf")
    }

    @Test func leavesUnknownAndLiteralBraces() {
        let template = Template(values: ["filename": "a.pdf"])
        #expect(template.expand(#"{"name": "{filename}", "x": {unknown}}"#)
                == #"{"name": "a.pdf", "x": {unknown}}"#)
        #expect(template.expand("{") == "{")
        #expect(template.expand("}{filename") == "}{filename")
    }

    @Test func joinsBatches() throws {
        let files = [try tempFile("a.pdf"), try tempFile("b.png")]
        let template = Template(files: files, endpointName: "X")
        #expect(template.expand("{filename} ({count})") == "a.pdf, b.png (2)")
    }
}

@Suite struct EncodingTests {
    @Test func multipartLayout() {
        var body = MultipartBody(boundary: "B")
        body.append(field: "note", value: "hi")
        body.append(file: "file", filename: "a\"b.pdf", mimeType: "application/pdf", contents: Data("PDF".utf8))
        let text = String(decoding: body.finalized(), as: UTF8.self)
        #expect(text == """
        --B\r
        Content-Disposition: form-data; name="note"\r
        \r
        hi\r
        --B\r
        Content-Disposition: form-data; name="file"; filename="a%22b.pdf"\r
        Content-Type: application/pdf\r
        \r
        PDF\r
        --B--\r

        """)
    }

    @Test func mimeEncodesDanishHeadersAndFilenames() {
        let message = MIMEMessage(
            fromAddress: "me@example.com", fromName: "Søren", to: ["bilag@example.com"], cc: [],
            subject: "Bilag: kvittering æøå", body: "Hej", attachments: [.init(filename: "Kvittering Føtex.pdf", mimeType: "application/pdf", data: Data("x".utf8))],
            boundary: "B"
        )
        let text = String(decoding: message.render(), as: UTF8.self)
        #expect(text.contains("From: =?UTF-8?B?\(Data("Søren".utf8).base64EncodedString())?= <me@example.com>\r\n"))
        #expect(text.contains("Subject: =?UTF-8?B?"))
        #expect(text.contains("filename=\"Kvittering Fotex.pdf\"; filename*=UTF-8''Kvittering%20F%C3%B8tex.pdf"))
        #expect(text.hasSuffix("--B--\r\n"))
        #expect(!text.contains("\n\n") && !text.contains("\r\r"))
    }

    @Test func dotStuffing() {
        let stuffed = String(decoding: SMTPSender.dotStuffed(Data(".a\r\nb\r\n.c".utf8)), as: UTF8.self)
        #expect(stuffed == "..a\r\nb\r\n..c\r\n.\r\n")
    }

    @Test func smtpHostCleanup() {
        #expect(SMTPSender.hostName(" smtp://smtp.gmail.com:587/ ") == "smtp.gmail.com")
        #expect(SMTPSender.hostName("smtp.simply.com") == "smtp.simply.com")
        let dns = NSError(domain: kCFErrorDomainCFNetwork as String, code: 2)
        #expect(SMTPSender.explain(dns, host: "smtp.x", port: 587).message.contains("Couldn't find the SMTP server"))
    }

    @Test func formEncoding() {
        #expect(DineroAuth.formEncode(["b": "x y", "a": "1&2"]) == "a=1%262&b=x%20y")
    }
}

@Suite struct ParserTests {
    @Test func smtpMultilineReply() {
        var buffer = Data("250-smtp.example.com\r\n250-STARTTLS\r\n250 AUTH PLAIN LOGIN\r\n220 next".utf8)
        let reply = SMTPReply.parse(from: &buffer)
        #expect(reply == SMTPReply(code: 250, lines: ["smtp.example.com", "STARTTLS", "AUTH PLAIN LOGIN"]))
        #expect(String(decoding: buffer, as: UTF8.self) == "220 next")
        #expect(SMTPReply.parse(from: &buffer) == nil)
    }
}

@Suite struct ModelTests {
    @Test func endpointRoundTrip() throws {
        var http = HTTPConfig()
        http.headers = [Header(name: "Authorization", isSecret: true)]
        let endpoints = [Endpoint.newDinero(), Endpoint.newEmail(), Endpoint(name: "H", symbol: "network", kind: .http(http))]
        let decoded = try JSONDecoder().decode([Endpoint].self, from: JSONEncoder().encode(endpoints))
        #expect(decoded == endpoints)
    }

    @Test func httpRequestBuilding() throws {
        var config = HTTPConfig()
        config.url = "https://example.com/upload/{basename}"
        config.bodyMode = .json
        config.headers = [Header(name: "X-Name", value: "{filename}")]
        let endpoint = Endpoint(name: "E", symbol: "network", kind: .http(config))
        let file = try tempFile("r.pdf", "PDF")
        let request = try HTTPSender(endpoint: endpoint, config: config, secrets: SecretStore(accessGroup: nil), session: .shared)
            .makeRequest(for: file)
        #expect(request.url?.absoluteString == "https://example.com/upload/r")
        #expect(request.value(forHTTPHeaderField: "X-Name") == "r.pdf")
        #expect(String(decoding: request.httpBody!, as: UTF8.self) == #"{"filename": "r.pdf", "data": "UERG"}"#)
    }

    @Test func dineroOrganizationsDecodeAnyCase() throws {
        let lower = try JSONDecoder().decode([DineroOrganization].self, from: Data(#"[{"id": 42, "name": "My ApS", "isPro": true}]"#.utf8))
        let upper = try JSONDecoder().decode([DineroOrganization].self, from: Data(#"[{"Id": 42, "Name": "My ApS"}]"#.utf8))
        #expect(lower == [DineroOrganization(id: 42, name: "My ApS")])
        #expect(upper == lower)
    }

    @Test func dineroRejectsWrongType() throws {
        let uploader = DineroUploader(endpointID: UUID(), config: DineroConfig(organizationID: 1), auth: DineroAuth(secrets: SecretStore(accessGroup: nil)), session: .shared)
        #expect(throws: SendError.self) { try uploader.validate(try tempFile("notes.docx")) }
        try uploader.validate(try tempFile("scan.PDF"))
    }
}

/// Talks to a real server; run with `SENDKIT_LIVE=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SENDKIT_LIVE"] == "1"))
struct LiveTests {
    @Test(arguments: [SMTPConfig.Security.startTLS, .tls])
    func smtpHandshakeReachesMailFrom(security: SMTPConfig.Security) async throws {
        var config = SMTPConfig()
        config.host = "smtp.gmail.com"
        config.security = security
        config.port = security.defaultPort
        config.fromAddress = "nobody@example.com"
        let draft = MailDraft(to: ["nobody@example.com"], cc: [], bcc: [], subject: "x", body: "x", attachments: [])
        let error = await #expect(throws: SendError.self) {
            try await SMTPSender(config: config, password: "", session: .shared).send(draft)
        }
        // Unauthenticated MAIL FROM is refused only after TLS + EHLO succeeded.
        #expect(error?.message.contains("after MAIL") == true, "\(error?.message ?? "")")
    }

    @Test func unknownHostIsExplained() async {
        var config = SMTPConfig()
        config.host = " smtp.does-not-exist-sharetoanything.dk "
        config.fromAddress = "nobody@example.com"
        let draft = MailDraft(to: ["nobody@example.com"], cc: [], bcc: [], subject: "x", body: "x", attachments: [])
        let error = await #expect(throws: SendError.self) {
            try await SMTPSender(config: config, password: "", session: .shared).send(draft)
        }
        #expect(error?.message == "Couldn't find the SMTP server “smtp.does-not-exist-sharetoanything.dk”. Check the Server field.", "\(error?.message ?? "")")
    }
}
