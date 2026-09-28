import SendKit
import SwiftUI

struct DineroEndpointEditor: View {
    @Binding var config: DineroConfig
    var endpointID: UUID

    @State private var clientID = DineroAuth().clientID
    @State private var clientSecret = DineroAuth().clientSecret
    @State private var apiKey: String
    @State private var organizations: [DineroOrganization] = []
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, checking, ok, failed(String)
    }

    init(config: Binding<DineroConfig>, endpointID: UUID) {
        _config = config
        self.endpointID = endpointID
        _apiKey = State(initialValue: DineroAuth().apiKey(endpointID: endpointID))
    }

    var body: some View {
        Section {
            Field("Client ID", text: $clientID, content: .code)
                .onChange(of: clientID) { _, value in DineroAuth().clientID = value; status = .idle }
            LabeledSecureField("Client secret", text: $clientSecret)
                .onChange(of: clientSecret) { _, value in DineroAuth().clientSecret = value; status = .idle }
        } header: {
            Text("Dinero credentials")
        } footer: {
            Text("From Dinero: Integrationer → Se og opret API-nøgler → Personlig integration → Anmod om API-credentials. Shared by all your Dinero endpoints.")
        }

        Section {
            LabeledSecureField("API key", text: $apiKey)
                .onChange(of: apiKey) { _, value in
                    SecretStore.shared.set(value.trimmingCharacters(in: .whitespacesAndNewlines),
                                           for: DineroAuth.apiKeyKey(endpointID: endpointID))
                    status = .idle
                }

            if organizations.count > 1 {
                Picker("Organization", selection: $config.organizationID) {
                    ForEach(organizations) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .onChange(of: config.organizationID) { _, id in
                    config.organizationName = organizations.first { $0.id == id }?.name ?? ""
                }
            } else {
                LabeledContent("Organization", value: config.organizationName.isEmpty ? "—" : config.organizationName)
            }

            HStack {
                Button("Check Connection") { Task { await check() } }
                    .disabled(apiKey.isEmpty || clientID.isEmpty || clientSecret.isEmpty || status == .checking)
                Spacer()
                switch status {
                case .idle: EmptyView()
                case .checking: ProgressView().controlSize(.small)
                case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            if case .failed(let message) = status {
                Text(message).foregroundStyle(.red).font(.callout)
            }
        } header: {
            Text("Organization")
        } footer: {
            Text("Create the API key inside the organization in Dinero. Files are uploaded to its Bilag inbox — PDFs and images up to 6 MB.")
        }
        .task {
            if config.organizationID == nil, !apiKey.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty { await check() }
        }
    }

    /// Logs in with the API key and picks up the organization it belongs to.
    private func check() async {
        status = .checking
        do {
            organizations = try await DineroAuth().organizations(apiKey: apiKey)
            if let current = config.organizationID, organizations.contains(where: { $0.id == current }) {
                config.organizationName = organizations.first { $0.id == current }!.name
            } else if let first = organizations.first {
                config.organizationID = first.id
                config.organizationName = first.name
            }
            status = organizations.isEmpty ? .failed("The API key doesn't give access to any organization.") : .ok
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
