import Foundation

public struct SendError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A prefilled email for the platform's compose UI.
public struct MailDraft: Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var body: String
    public var attachments: [SharedFile]
}

public enum SendOutcome: Sendable {
    /// Delivered; the string is a human-readable summary.
    case sent(String)
    /// The caller must present the draft in a mail compose UI.
    case draft(MailDraft)
}

/// Sends files to an endpoint. Used by the macOS agent and the iOS share extension.
public struct Sender: Sendable {
    public var secrets: SecretStore
    public var session: URLSession

    public init(secrets: SecretStore = .shared, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    public func send(_ originals: [SharedFile], to endpoint: Endpoint) async throws -> SendOutcome {
        guard !originals.isEmpty else { throw SendError("No files to send.") }
        if let rejected = originals.first(where: { !endpoint.accepts($0.url) }) {
            throw SendError("\(endpoint.name) doesn't accept .\(rejected.ext) files (\(rejected.filename)).")
        }

        var preparation = endpoint.prepare
        if case .dinero = endpoint.kind {
            // Dinero rejects anything over 6 MB, so always shrink images to fit.
            let dineroLimit = Double(DineroUploader.maxSize) / 1_048_576 - 0.2
            if preparation.maxSizeMB == 0 || preparation.maxSizeMB > dineroLimit { preparation.maxSizeMB = dineroLimit }
        }
        let preparer = FilePreparer(preparation: preparation, endpointName: endpoint.name)
        let files = try preparer.prepare(originals)

        let outcome: SendOutcome
        do {
            outcome = try await deliver(files, originals: originals, to: endpoint)
        } catch {
            preparer.cleanUp()
            throw error
        }
        // A draft still needs the prepared attachments; the system clears the temporary folder later.
        guard case .sent(let message) = outcome else { return outcome }
        preparer.cleanUp()
        if let problem = endpoint.afterSend.apply(to: originals) {
            return .sent("\(message) — but \(problem)")
        }
        return outcome
    }

    private func deliver(_ files: [SharedFile], originals: [SharedFile], to endpoint: Endpoint) async throws -> SendOutcome {
        switch endpoint.kind {
        case .http(let config):
            for file in files {
                try await HTTPSender(endpoint: endpoint, config: config, secrets: secrets, session: session).send(file)
            }
            return .sent("Sent \(Self.describe(files)) to \(endpoint.name)")

        case .dinero(let config):
            let uploader = DineroUploader(endpointID: endpoint.id, config: config, auth: DineroAuth(secrets: secrets, session: session), session: session)
            for file in files { try uploader.validate(file) }
            for file in files { try await uploader.upload(file) }
            return .sent("Uploaded \(Self.describe(files)) to Dinero")

        case .folder(let config):
            try config.deliver(files, originals: originals, endpointName: endpoint.name)
            return .sent("\(config.move ? "Moved" : "Copied") \(Self.describe(files)) to \(config.folderURL?.lastPathComponent ?? "folder")")

        case .email(let config):
            let template = Template(files: files, endpointName: endpoint.name)
            let draft = MailDraft(
                to: config.toList.map(template.expand),
                cc: config.ccList.map(template.expand),
                bcc: config.bccList.map(template.expand),
                subject: template.expand(config.subject),
                body: template.expand(config.body),
                attachments: files
            )
            switch config.delivery {
            case .draft:
                return .draft(draft)
            case .smtp:
                guard !draft.to.isEmpty else { throw SendError("\(endpoint.name) has no recipients.") }
                let password = secrets.get(SMTPConfig.passwordKey(endpointID: endpoint.id)) ?? ""
                try await SMTPSender(config: config.smtp, password: password, session: session).send(draft)
                return .sent("Emailed \(Self.describe(files)) to \(draft.to.joined(separator: ", "))")
            }
        }
    }

    static func describe(_ files: [SharedFile]) -> String {
        files.count == 1 ? files[0].filename : "\(files.count) files"
    }
}
