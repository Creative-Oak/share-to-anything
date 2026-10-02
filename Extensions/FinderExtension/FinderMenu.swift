import AppKit
import FinderSync
import SendKit

/// Adds "Send to ▸ <endpoint>" to Finder's context menu and hands the selection to the main app.
final class FinderMenu: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let endpoints = EndpointStore.load()
        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        let submenu = NSMenu(title: "Send to")

        if endpoints.isEmpty {
            submenu.addItem(withTitle: "Add endpoints…", action: #selector(openApp(_:)), keyEquivalent: "")
        } else if !endpoints.contains(where: { $0.isOffered(for: selection) }) {
            submenu.addItem(withTitle: "No endpoint accepts this file type", action: nil, keyEquivalent: "")
            submenu.addItem(withTitle: "Edit endpoints…", action: #selector(openApp(_:)), keyEquivalent: "")
        } else {
            // Finder copies the menu, so `representedObject` is lost; the tag indexes into the endpoint list.
            for (index, endpoint) in endpoints.enumerated() where endpoint.isOffered(for: selection) {
                let item = NSMenuItem(title: endpoint.name, action: #selector(send(_:)), keyEquivalent: "")
                item.tag = index
                item.image = NSImage(systemSymbolName: endpoint.symbol, accessibilityDescription: nil)
                submenu.addItem(item)
            }
        }

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "Send to", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func send(_ sender: NSMenuItem) {
        let endpoints = EndpointStore.load()
        guard endpoints.indices.contains(sender.tag),
              let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty else { return }

        var components = URLComponents()
        components.scheme = AppConfig.urlScheme
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "endpoint", value: endpoints[sender.tag].id.uuidString)]
            + selection.map { URLQueryItem(name: "file", value: $0.path) }
        if let url = components.url { open(url) }
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        open(URL(string: "\(AppConfig.urlScheme)://settings")!)
    }

    private func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
