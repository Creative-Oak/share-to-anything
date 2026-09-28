import AppKit
import SendKit
import SwiftUI

/// The small "Send to" chooser shown when files are opened with the app (Mail's attachment
/// menu "Open in ▸ Share to Anything", Finder's "Open With"). It drops down from the menu
/// bar icon, or appears as a centered panel when the icon can't be found.
@MainActor
final class SendPanelController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let store: EndpointStore
    private let agent: Agent
    private let openSettings: () -> Void
    private var popover: NSPopover?
    private var panel: NSPanel?
    private var files: [URL] = []

    init(store: EndpointStore, agent: Agent, openSettings: @escaping () -> Void) {
        self.store = store
        self.agent = agent
        self.openSettings = openSettings
    }

    /// Files opened while the chooser is up (e.g. several attachments) join the same send.
    func show(_ urls: [URL]) {
        files += urls.filter { !files.contains($0) }
        store.reload()
        present()
    }

    /// When the app is launched to open a file, the menu bar icon appears a moment later,
    /// so wait for it briefly before settling for the panel.
    private func present(attempt: Int = 0) {
        if popover == nil, panel == nil, Self.menuBarIcon() == nil, attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.present(attempt: attempt + 1) }
            return
        }

        let hosting = NSHostingController(rootView: SendPanelView(
            files: files,
            endpoints: store.endpoints,
            onSelect: { [weak self] in self?.send(to: $0) },
            onCancel: { [weak self] in self?.close() },
            onSettings: { [weak self] in
                self?.close()
                self?.openSettings()
            }
        ))
        hosting.sizingOptions = .preferredContentSize
        NSApp.activate()

        if let popover {
            popover.contentViewController = hosting
        } else if let panel {
            panel.contentViewController = hosting
            panel.makeKeyAndOrderFront(nil)
        } else if let icon = Self.menuBarIcon() {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = hosting
            popover.show(relativeTo: icon.bounds, of: icon, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            self.popover = popover
        } else {
            let panel = makePanel()
            panel.contentViewController = hosting
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            self.panel = panel
        }
    }

    /// The view of the app's status item. MenuBarExtra doesn't expose its NSStatusItem, but its
    /// button lives in the app's only status bar window.
    private static func menuBarIcon() -> NSView? {
        NSApp.windows
            .first { window in
                // Right after launch the window exists but hasn't been placed in the menu bar yet.
                String(describing: type(of: window)).contains("StatusBarWindow") && window.isVisible
                    && window.frame.height > 0 && NSScreen.screens.contains { $0.frame.contains(window.frame) }
            }?
            .contentView
    }

    private func send(to endpoint: Endpoint) {
        let files = files.map(SharedFile.init(url:))
        close()
        Task { await agent.send(files, to: endpoint, cleanup: false) }
    }

    private func close() {
        popover?.performClose(nil)
        panel?.close()
    }

    private func makePanel() -> NSPanel {
        let panel = CancellablePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                                     styleMask: [.titled, .closable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        return panel
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        files = []
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        files = []
    }
}

/// Closes on Escape, like a sheet.
private final class CancellablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct SendPanelView: View {
    var files: [URL]
    var endpoints: [Endpoint]
    var onSelect: (Endpoint) -> Void
    var onCancel: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()

            if endpoints.isEmpty {
                ContentUnavailableView {
                    Label("No endpoints", systemImage: "paperplane")
                } description: {
                    Text("Add an endpoint to send files to.")
                } actions: {
                    Button("Open Settings…", action: onSettings)
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(endpoints.prefix(9).enumerated()), id: \.element.id) { index, endpoint in
                        EndpointButton(endpoint: endpoint, shortcut: index + 1) { onSelect(endpoint) }
                    }
                    // More than nine is unusual; they're still reachable, just without a shortcut.
                    ForEach(endpoints.dropFirst(9)) { endpoint in
                        EndpointButton(endpoint: endpoint, shortcut: nil) { onSelect(endpoint) }
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Button("Settings…", action: onSettings)
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(files.count == 1 ? "Send “\(files[0].lastPathComponent)”" : "Send \(files.count) files")
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: NSImage {
        files.count == 1
            ? NSWorkspace.shared.icon(forFile: files[0].path)
            : NSWorkspace.shared.icon(for: .data)
    }

    private var detail: String {
        let size = files.map(\.path).reduce(0) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0)
        }
        let formatted = size.formatted(.byteCount(style: .file))
        return files.count == 1
            ? formatted
            : "\(files.map(\.lastPathComponent).joined(separator: ", ")) · \(formatted)"
    }
}

private struct EndpointButton: View {
    var endpoint: Endpoint
    var shortcut: Int?
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: endpoint.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(endpoint.name)
                    Text(endpoint.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .modifier(NumberShortcut(number: shortcut))
    }
}

private struct NumberShortcut: ViewModifier {
    var number: Int?

    func body(content: Content) -> some View {
        if let number, let key = "\(number)".first {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            content
        }
    }
}

