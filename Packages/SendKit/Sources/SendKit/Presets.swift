import Foundation

/// A ready-made endpoint configuration offered in the "Add Endpoint" gallery.
public struct EndpointPreset: Identifiable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case accounting = "Accounting"
        case documents = "Documents & storage"
        case messaging = "Messaging"
        case automation = "Automation"
        case custom = "Custom"
    }

    public var id: String
    public var category: Category
    public var summary: String
    /// The template; `make()` hands out a copy with fresh identifiers.
    var template: Endpoint
    var macOnly = false

    public var name: String { template.name }
    public var symbol: String { template.symbol }

    public var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        !macOnly
        #endif
    }

    public func make() -> Endpoint { template.withFreshIdentifiers() }
}

extension EndpointPreset {
    static let receiptTypes = "pdf, jpg, jpeg, png, heic"

    public static let all: [EndpointPreset] = [
        // MARK: Accounting
        EndpointPreset(id: "dinero", category: .accounting,
                       summary: "Upload receipts to the Bilag inbox through the Dinero API.",
                       template: .newDinero()),
        emailPreset(id: "dinero-mail", name: "Dinero (email)", category: .accounting,
                    summary: "Email receipts to your organization's bilag address.",
                    hint: "Paste your organization's bilag email address from Dinero into To."),
        emailPreset(id: "economic", name: "e-conomic", category: .accounting,
                    summary: "Email receipts to your e-conomic inbox address.",
                    hint: "Paste your agreement's inbox email address from e-conomic into To."),
        emailPreset(id: "billy", name: "Billy", category: .accounting,
                    summary: "Email receipts to your Billy bilag address.",
                    hint: "Paste your organization's bilag email address from Billy into To."),
        emailPreset(id: "expensify", name: "Expensify", category: .accounting,
                    summary: "Email receipts to Expensify.", to: "receipts@expensify.com",
                    hint: "Expensify matches receipts by sender, so send from the email address of your Expensify account (SMTP “From address”, or your Mail account)."),

        // MARK: Documents & storage
        EndpointPreset(id: "folder", category: .documents,
                       summary: "Copy or move files into a folder, optionally renamed.",
                       template: .newFolder(), macOnly: true),
        httpPreset(id: "paperless", name: "Paperless-ngx", symbol: "archivebox", category: .documents,
                   summary: "Add documents to a Paperless-ngx server.",
                   hint: "Replace the host in the URL and paste an API token (Paperless → My Profile) as the secret.") {
            $0.url = "https://paperless.example.com/api/documents/post_document/"
            $0.fileField = "document"
            $0.formFields = [FormField(name: "title", value: "{basename}")]
            $0.headers = [Header(name: "Authorization", value: "Token {secret}")]
        },
        httpPreset(id: "webdav", name: "Nextcloud / WebDAV", symbol: "cloud", category: .documents,
                   summary: "Upload to Nextcloud, ownCloud, Synology or any WebDAV folder.",
                   hint: "Set the host, user and folder in the URL, your username below, and an app password as the secret.") {
            $0.method = .PUT
            $0.url = "https://cloud.example.com/remote.php/dav/files/USERNAME/Documents/{filename}"
            $0.bodyMode = .raw
            $0.username = "USERNAME"
        },

        // MARK: Messaging
        httpPreset(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right", category: .messaging,
                   summary: "Post files to a channel through a webhook.",
                   hint: "Paste the channel's webhook URL (Channel settings → Integrations → Webhooks) as the URL.") {
            $0.url = "https://discord.com/api/webhooks/…"
            $0.fileField = "files[0]"
            $0.formFields = [FormField(name: "content", value: "{filename}")]
        },
        httpPreset(id: "telegram", name: "Telegram", symbol: "paperplane", category: .messaging,
                   summary: "Send files to yourself or a group with a bot.",
                   hint: "Create a bot with @BotFather and paste its token as the secret. Put your chat ID in the chat_id field (message @userinfobot to find it).") {
            $0.url = "https://api.telegram.org/bot{secret}/sendDocument"
            $0.fileField = "document"
            $0.formFields = [FormField(name: "chat_id", value: ""), FormField(name: "caption", value: "{filename}")]
        },
        httpPreset(id: "ntfy", name: "ntfy", symbol: "bell", category: .messaging,
                   summary: "Push a file to your phone through an ntfy topic.",
                   hint: "Replace “my-topic” in the URL with your own hard-to-guess topic name.") {
            $0.method = .PUT
            $0.url = "https://ntfy.sh/my-topic"
            $0.bodyMode = .raw
            $0.headers = [Header(name: "Filename", value: "{filename}")]
        },

        // MARK: Automation
        httpPreset(id: "webhook", name: "Webhook (n8n, Zapier, Make)", symbol: "bolt", category: .automation,
                   summary: "Send the file to an automation webhook.",
                   hint: "Paste the webhook URL from your workflow's trigger step. The file arrives in the “file” field.") {
            $0.url = "https://"
            $0.formFields = [FormField(name: "filename", value: "{filename}"), FormField(name: "sent", value: "{datetime}")]
        },

        // MARK: Custom
        EndpointPreset(id: "http", category: .custom,
                       summary: "Any URL: multipart, raw or JSON, with your own headers.",
                       template: Endpoint(name: "HTTP endpoint", symbol: "network", kind: .http(HTTPConfig()))),
        EndpointPreset(id: "email", category: .custom,
                       summary: "A prefilled email: review it in Mail or send it over SMTP.",
                       template: Endpoint(name: "Email", symbol: "envelope", kind: .email(EmailConfig()))),
    ]

    private static func httpPreset(id: String, name: String, symbol: String, category: Category, summary: String,
                                   hint: String, configure: (inout HTTPConfig) -> Void) -> EndpointPreset {
        var config = HTTPConfig()
        configure(&config)
        return EndpointPreset(id: id, category: category, summary: summary,
                              template: Endpoint(name: name, symbol: symbol, kind: .http(config), hint: hint))
    }

    private static func emailPreset(id: String, name: String, category: Category, summary: String,
                                    to: String = "", hint: String) -> EndpointPreset {
        var config = EmailConfig()
        config.to = to
        config.subject = "{filename}"
        config.body = ""
        return EndpointPreset(id: id, category: category, summary: summary,
                              template: Endpoint(name: name, symbol: "envelope", kind: .email(config),
                                                 hint: hint, fileTypes: receiptTypes))
    }
}

// MARK: - Import / export

extension Endpoint {
    /// A copy that shares no identifiers (and therefore no Keychain items) with the original.
    public func withFreshIdentifiers() -> Endpoint {
        var copy = self
        copy.id = UUID()
        if case .http(var config) = copy.kind {
            config.headers = config.headers.map { Header(name: $0.name, value: $0.value, isSecret: $0.isSecret) }
            config.formFields = config.formFields.map { FormField(name: $0.name, value: $0.value) }
            copy.kind = .http(config)
        }
        return copy
    }

    /// Keychain accounts holding this endpoint's secrets, in a stable order.
    var secretKeys: [String] {
        switch kind {
        case .http(let config):
            [secretKey] + config.headers.filter(\.isSecret).map { $0.secretKey(endpointID: id) }
        case .email: [SMTPConfig.passwordKey(endpointID: id)]
        case .dinero: [DineroAuth.apiKeyKey(endpointID: id)]
        case .folder: []
        }
    }

    /// A copy named "… copy" that gets its own Keychain items holding the same secrets.
    public func duplicate(secrets: SecretStore = .shared) -> Endpoint {
        var copy = withFreshIdentifiers()
        copy.name += " copy"
        for (from, to) in zip(secretKeys, copy.secretKeys) {
            if let value = secrets.get(from) { secrets.set(value, for: to) }
        }
        return copy
    }

    /// JSON for sharing. Secrets live in the Keychain and are never part of it.
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func importing(_ data: Data) throws -> Endpoint {
        do {
            return try JSONDecoder().decode(Endpoint.self, from: data).withFreshIdentifiers()
        } catch {
            throw SendError("That file isn't a Share to Anything endpoint.")
        }
    }
}
