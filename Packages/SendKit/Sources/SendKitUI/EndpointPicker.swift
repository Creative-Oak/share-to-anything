import SendKit
import SwiftUI

/// The endpoint chooser shown by the share extensions.
public struct EndpointPicker: View {
    public enum Status: Equatable {
        case idle
        case sending(String)
        case done(String)
        case failed(String)
    }

    var endpoints: [Endpoint]
    var fileSummary: String
    var status: Status
    var onSelect: (Endpoint) -> Void
    var onCancel: () -> Void

    public init(endpoints: [Endpoint], fileSummary: String, status: Status,
                onSelect: @escaping (Endpoint) -> Void, onCancel: @escaping () -> Void) {
        self.endpoints = endpoints
        self.fileSummary = fileSummary
        self.status = status
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Send to")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isFinished ? "Close" : "Cancel", action: onCancel)
                    }
                }
        }
        #if os(macOS)
        .frame(width: 340, height: 380)
        #endif
    }

    private var isFinished: Bool {
        if case .done = status { return true }
        if case .failed = status { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle:
            List {
                Section {
                    ForEach(endpoints) { endpoint in
                        Button { onSelect(endpoint) } label: {
                            EndpointRow(endpoint: endpoint)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(fileSummary)
                }
            }
            .overlay {
                if endpoints.isEmpty {
                    ContentUnavailableView("No endpoints", systemImage: "paperplane",
                                           description: Text("No endpoint accepts these files. Open Share to Anything to add or edit one."))
                }
            }
        case .sending(let message):
            ProgressView(message).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let message):
            ContentUnavailableView(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            ContentUnavailableView("Couldn't send", systemImage: "exclamationmark.triangle.fill",
                                   description: Text(message))
        }
    }
}
