import SendKit
import SwiftUI

/// File-type filter and pre-send preparation.
struct FilesSection: View {
    @Binding var endpoint: Endpoint

    private var isDinero: Bool { if case .dinero = endpoint.kind { true } else { false } }

    var body: some View {
        Section {
            Field("File types", text: $endpoint.fileTypes, prompt: isDinero ? "PDFs and images" : "All files", content: .code)
            if !isDinero {
                Button("Only PDFs and Images") { endpoint.fileTypes = "pdf, jpg, jpeg, png, heic" }
                    .disabled(endpoint.fileTypes == "pdf, jpg, jpeg, png, heic")
            }
        } header: {
            Text("Files")
        } footer: {
            Text("Comma-separated extensions, like “pdf, jpg”. The endpoint is only offered when every selected file matches.")
        }

        Section {
            Picker("Images", selection: $endpoint.prepare.imageFormat) {
                ForEach(Preparation.ImageFormat.allCases, id: \.self) { Text($0.label) }
            }
            LabeledContent("Shrink images over") {
                HStack(spacing: 4) {
                    TextField("Size", value: $endpoint.prepare.maxSizeMB, format: .number.precision(.fractionLength(0...1)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("MB").foregroundStyle(.secondary)
                }
            }
            Field("Rename to", text: $endpoint.prepare.rename, prompt: "{date} {basename}.{ext}", content: .code)
        } header: {
            Text("Before sending")
        } footer: {
            Text(isDinero
                 ? "Images are always shrunk to fit Dinero's 6 MB limit. Your original files are never changed."
                 : "0 MB means no limit. Shrunk images are saved as JPEG. Your original files are never changed.")
        }
    }
}

#if os(macOS)
/// Finder tag and archive folder for the original file.
struct AfterSendSection: View {
    @Binding var afterSend: AfterSend

    var body: some View {
        Section {
            Field("Add Finder tag", text: $afterSend.tag, prompt: "None")
            FolderField("Move original to", path: $afterSend.moveTo, prompt: "Leave in place")
        } header: {
            Text("After sending")
        } footer: {
            Text("Applied on this Mac once the file was sent successfully. Email drafts don't count as sent.")
        }
    }
}

struct FolderEditor: View {
    @Binding var config: FolderConfig

    var body: some View {
        Section {
            FolderField("Folder", path: $config.path, prompt: "~/Documents/Receipts")
            Picker("Action", selection: $config.move) {
                Text("Copy").tag(false)
                Text("Move").tag(true)
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("Use “Rename to” below to file things as, for example, “{date} {basename}.{ext}”.")
        }
    }
}

/// A path field with a Choose… button.
struct FolderField: View {
    var label: String
    @Binding var path: String
    var prompt: String
    @State private var isChoosing = false

    init(_ label: String, path: Binding<String>, prompt: String) {
        self.label = label
        _path = path
        self.prompt = prompt
    }

    var body: some View {
        HStack {
            Field(label, text: $path, prompt: prompt, content: .code)
            Button("Choose…") { isChoosing = true }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if let url = try? result.get() {
                // "~/…" keeps the endpoint working on another Mac with a different user name.
                path = (url.path as NSString).abbreviatingWithTildeInPath
            }
        }
    }
}
#endif

/// Sends a small sample PDF through the endpoint as currently configured.
struct TestSendSection: View {
    var endpoint: Endpoint
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, sending, done(String), failed(String)
    }

    var body: some View {
        Section {
            HStack {
                Button("Send Test File") { Task { await send() } }
                    .disabled(status == .sending)
                Spacer()
                switch status {
                case .idle: EmptyView()
                case .sending: ProgressView().controlSize(.small)
                case .done: Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            switch status {
            case .done(let message): Text(message).font(.callout).foregroundStyle(.secondary)
            case .failed(let message): Text(message).font(.callout).foregroundStyle(.red)
            default: EmptyView()
            }
        } footer: {
            Text("Sends a one-page PDF named “Share to Anything test.pdf”.")
        }
        .onChange(of: endpoint) { status = .idle }
    }

    private func send() async {
        status = .sending
        do {
            let file = try SampleFile.make()
            // The test must not tag or move anything, and the sample is a PDF whatever the filter says.
            var endpoint = endpoint
            endpoint.afterSend = AfterSend()
            endpoint.fileTypes = ""
            switch try await Sender().send([file], to: endpoint) {
            case .sent(let message):
                status = .done(message)
            case .draft(let draft):
                #if os(macOS)
                try MailComposer.present(draft)
                status = .done("Draft opened in your mail app.")
                #else
                status = .done("This endpoint opens a draft to \(draft.to.joined(separator: ", ")) with the subject “\(draft.subject)” when you share a file.")
                #endif
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
