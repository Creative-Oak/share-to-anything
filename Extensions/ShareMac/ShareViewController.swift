import AppKit
import SendKit
import SendKitUI
import SwiftUI
import UniformTypeIdentifiers

/// macOS share extension: pick an endpoint, then hand the files to the menu bar agent,
/// which does the sending (and survives this sheet closing).
final class ShareViewController: NSViewController {
    private var files: [URL] = []
    private var cleanup = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 380))
        render(status: .sending("Preparing…"))
        Task { await loadFiles() }
    }

    private func render(status: EndpointPicker.Status) {
        let picker = EndpointPicker(
            endpoints: EndpointStore.load(),
            fileSummary: files.count == 1 ? files[0].lastPathComponent : "\(files.count) files",
            status: status,
            onSelect: { [weak self] in self?.handOff(to: $0) },
            onCancel: { [weak self] in self?.cancel() }
        )
        view.subviews.forEach { $0.removeFromSuperview() }
        let host = NSHostingView(rootView: picker)
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
    }

    private func loadFiles() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let requestFolder = AppConfig.outboxURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                // The agent isn't sandboxed and can read the original path directly.
                files.append(url)
            } else if let copy = try? await Self.copyFileRepresentation(of: provider, into: requestFolder) {
                files.append(copy)
                cleanup = true
            }
        }
        render(status: files.isEmpty ? .failed("Nothing shareable was found.") : .idle)
    }

    /// Copies data-only items (e.g. images from Photos, attachments from Mail) into the shared Outbox.
    private static func copyFileRepresentation(of provider: NSItemProvider, into folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) ?? false } ?? UTType.data.identifier
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? SendError("Couldn't read the shared item."))
                    return
                }
                let name = provider.suggestedName.map { name in
                    url.pathExtension.isEmpty || name.hasSuffix(".\(url.pathExtension)") ? name : "\(name).\(url.pathExtension)"
                } ?? url.lastPathComponent
                let destination = folder.appending(path: name)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handOff(to endpoint: Endpoint) {
        var components = URLComponents()
        components.scheme = AppConfig.urlScheme
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "endpoint", value: endpoint.id.uuidString)]
            + files.map { URLQueryItem(name: "file", value: $0.path) }
            + (cleanup ? [URLQueryItem(name: "cleanup", value: "1")] : [])
        guard let url = components.url else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.render(status: .failed("Couldn't reach Share to Anything: \(error.localizedDescription)"))
                } else {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
