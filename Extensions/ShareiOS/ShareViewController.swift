import MessageUI
import SendKit
import SendKitUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS share extension: pick an endpoint and send in-process.
final class ShareViewController: UIViewController, MFMailComposeViewControllerDelegate {
    private var files: [SharedFile] = []
    private var host: UIHostingController<EndpointPicker>?
    private lazy var workFolder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    override func viewDidLoad() {
        super.viewDidLoad()
        render(status: .sending("Preparing…"))
        Task { await loadFiles() }
    }

    private func render(status: EndpointPicker.Status) {
        let picker = EndpointPicker(
            endpoints: EndpointStore.load().filter { $0.isOffered(for: files.map(\.url)) },
            fileSummary: files.count == 1 ? files[0].filename : "\(files.count) files",
            status: status,
            onSelect: { [weak self] endpoint in Task { await self?.send(to: endpoint) } },
            onCancel: { [weak self] in self?.finish() }
        )
        if let host {
            host.rootView = picker
            return
        }
        let host = UIHostingController(rootView: picker)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        self.host = host
    }

    private func loadFiles() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        try? FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        for provider in providers {
            if let url = try? await copy(provider) { files.append(SharedFile(url: url)) }
        }
        render(status: files.isEmpty ? .failed("Nothing shareable was found.") : .idle)
    }

    /// The provider's file is deleted when the callback returns, so copy it out first.
    private func copy(_ provider: NSItemProvider) async throws -> URL {
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) ?? false } ?? UTType.data.identifier
        let folder = workFolder
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? SendError("Couldn't read the shared item."))
                    return
                }
                let name = suggestedName.map { name in
                    url.pathExtension.isEmpty || name.hasSuffix(".\(url.pathExtension)") ? name : "\(name).\(url.pathExtension)"
                } ?? url.lastPathComponent
                let destination = folder.appending(path: name)
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func send(to endpoint: Endpoint) async {
        render(status: .sending("Sending to \(endpoint.name)…"))
        let names = files.map(\.filename)
        do {
            switch try await Sender().send(files, to: endpoint) {
            case .sent(let message):
                SendHistory.append(SendRecord(endpointName: endpoint.name, files: names, success: true, message: message))
                render(status: .done(message))
                try? await Task.sleep(for: .seconds(1.2))
                finish()
            case .draft(let draft):
                present(try MailComposer.makeController(draft, delegate: self), animated: true)
            }
        } catch {
            SendHistory.append(SendRecord(endpointName: endpoint.name, files: names, success: false, message: error.localizedDescription))
            render(status: .failed(error.localizedDescription))
        }
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                           didFinishWith result: MFMailComposeResult, error: Error?) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true) {
                if let error {
                    self.render(status: .failed(error.localizedDescription))
                } else if result == .cancelled {
                    self.render(status: .idle)
                } else {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        try? FileManager.default.removeItem(at: workFolder)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
