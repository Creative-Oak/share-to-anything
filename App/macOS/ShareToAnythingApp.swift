import SendKit
import SwiftUI

@main
struct ShareToAnythingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(agent: delegate.agent) { delegate.settings.show() }
        } label: {
            Image(systemName: delegate.agent.activeSends > 0 ? "paperplane.fill" : "paperplane")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = EndpointStore(syncsWithICloud: true)
    lazy var agent = Agent(store: store)
    lazy var settings = SettingsWindowController(store: store)
    lazy var sendPanel = SendPanelController(store: store, agent: agent) { [unowned self] in settings.show() }
    private var launchedWithURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        agent.requestNotificationPermission()
        // First run (or launched from Xcode/Finder with nothing set up): show settings.
        if store.endpoints.isEmpty, !launchedWithURL { settings.show() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithURL = true
        // Documents opened with the app (Mail's "Open in", Finder's "Open With") get the send panel.
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { sendPanel.show(files) }
        for url in urls where !url.isFileURL {
            if url.host == "settings" { settings.show() } else { agent.handle(url) }
        }
    }

    /// Opening the app again (Finder, Spotlight, Xcode) shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}
