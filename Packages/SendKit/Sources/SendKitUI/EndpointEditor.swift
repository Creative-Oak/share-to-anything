import SendKit
import SwiftUI

/// Edits a copy of an endpoint and saves it back after a short pause in typing.
struct EndpointEditor: View {
    @Environment(EndpointStore.self) private var store
    @State private var draft: Endpoint

    init(endpoint: Endpoint) {
        _draft = State(initialValue: endpoint)
    }

    var body: some View {
        Form {
            Section {
                Field("Name", text: $draft.name)
                SymbolPicker(selection: $draft.symbol)
            } footer: {
                Text("Shown in the Finder “Send to” menu and the share sheet.")
            }

            switch draft.kind {
            case .http:
                HTTPEditor(config: httpConfig, endpointID: draft.id)
            case .email:
                EmailEditor(config: emailConfig, endpointID: draft.id)
            case .dinero:
                DineroEndpointEditor(config: dineroConfig, endpointID: draft.id)
            }

            Section {
                Text(Template.placeholders.map { "{\($0)}" }.joined(separator: "  "))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Placeholders")
            } footer: {
                Text("Use these in any text field above. They're filled in when a file is sent.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
        #if os(macOS)
        .navigationSubtitle(draft.kindLabel)
        #endif
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, draft != store.endpoint(id: draft.id) else { return }
            store.upsert(draft)
        }
        .onDisappear {
            if draft != store.endpoint(id: draft.id), store.endpoint(id: draft.id) != nil { store.upsert(draft) }
        }
    }

    private var httpConfig: Binding<HTTPConfig> {
        Binding(get: { if case .http(let config) = draft.kind { config } else { HTTPConfig() } },
                set: { draft.kind = .http($0) })
    }

    private var emailConfig: Binding<EmailConfig> {
        Binding(get: { if case .email(let config) = draft.kind { config } else { EmailConfig() } },
                set: { draft.kind = .email($0) })
    }

    private var dineroConfig: Binding<DineroConfig> {
        Binding(get: { if case .dinero(let config) = draft.kind { config } else { DineroConfig() } },
                set: { draft.kind = .dinero($0) })
    }
}

// MARK: - HTTP

struct HTTPEditor: View {
    @Binding var config: HTTPConfig
    var endpointID: UUID

    var body: some View {
        Section("Request") {
            Picker("Method", selection: $config.method) {
                ForEach(HTTPConfig.Method.allCases, id: \.self) { Text($0.rawValue) }
            }
            Field("URL", text: $config.url, prompt: "https://example.com/upload", content: .url)
            Picker("Body", selection: $config.bodyMode) {
                ForEach(HTTPConfig.BodyMode.allCases, id: \.self) { Text($0.label) }
            }
            switch config.bodyMode {
            case .multipart:
                Field("File field", text: $config.fileField, prompt: "file", content: .code)
            case .raw:
                EmptyView()
            case .json:
                Field("JSON template", text: $config.jsonTemplate, content: .code, multiline: true)
            }
        }

        if config.bodyMode == .multipart {
            Section("Extra form fields") {
                ForEach($config.formFields) { $field in
                    HStack {
                        TextField("Name", text: $field.name, prompt: Text("Name"))
                        TextField("Value", text: $field.value, prompt: Text("Value"))
                    }
                    .labelsHidden()
                    .contextMenu { Button("Delete", role: .destructive) { config.formFields.removeAll { $0.id == field.id } } }
                }
                .onDelete { config.formFields.remove(atOffsets: $0) }
                Button("Add Field", systemImage: "plus") { config.formFields.append(FormField()) }
            }
        }

        Section {
            ForEach($config.headers) { $header in
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Header", text: $header.name, prompt: Text("Header name"))
                            .labelsHidden()
                        Toggle("Secret", isOn: $header.isSecret)
                            .fixedSize()
                    }
                    if header.isSecret {
                        SecretField("Value", key: header.secretKey(endpointID: endpointID))
                    } else {
                        TextField("Value", text: $header.value, prompt: Text("Value"))
                            .labelsHidden()
                    }
                }
                .contextMenu { Button("Delete", role: .destructive) { config.headers.removeAll { $0.id == header.id } } }
            }
            .onDelete { config.headers.remove(atOffsets: $0) }
            Button("Add Header", systemImage: "plus") { config.headers.append(Header()) }
        } header: {
            Text("Headers")
        } footer: {
            Text("Mark API keys and tokens as secret so they sync via iCloud Keychain instead of plain settings.")
        }
    }
}

// MARK: - Email

struct EmailEditor: View {
    @Binding var config: EmailConfig
    var endpointID: UUID

    var body: some View {
        Section {
            Field("To", text: $config.to, prompt: "bilag@example.com", content: .email)
            Field("Cc", text: $config.cc, prompt: "Optional", content: .email)
            Field("Bcc", text: $config.bcc, prompt: "Optional", content: .email)
        } header: {
            Text("Recipients")
        } footer: {
            Text("Separate several addresses with commas. For Dinero, use your organization's bilag email address.")
        }

        Section("Message") {
            Field("Subject", text: $config.subject)
            Field("Body", text: $config.body, multiline: true)
        }

        Section {
            Picker("Delivery", selection: $config.delivery) {
                ForEach(EmailConfig.Delivery.allCases, id: \.self) { Text($0.label) }
            }
        } footer: {
            #if os(macOS)
            if config.delivery == .draft {
                Text("Opens a new message in Mail for you to review. Cc and Bcc can't be prefilled this way on macOS.")
            }
            #endif
        }

        if config.delivery == .smtp {
            Section {
                Field("Server", text: $config.smtp.host, prompt: "smtp.example.com", content: .url)
                Picker("Security", selection: $config.smtp.security) {
                    ForEach(SMTPConfig.Security.allCases, id: \.self) { Text($0.label) }
                }
                .onChange(of: config.smtp.security) { _, security in config.smtp.port = security.defaultPort }
                NumberField("Port", value: $config.smtp.port)
                Field("Username", text: $config.smtp.username, content: .email)
                SecretField("Password", key: SMTPConfig.passwordKey(endpointID: endpointID))
                Field("From address", text: $config.smtp.fromAddress, prompt: "Same as username", content: .email)
                Field("From name", text: $config.smtp.fromName, prompt: "Optional")
            } header: {
                Text("SMTP")
            } footer: {
                Text("Gmail, iCloud and Outlook need an app-specific password. iCloud: smtp.mail.me.com, STARTTLS 587. Gmail: smtp.gmail.com.")
            }
        }
    }
}
