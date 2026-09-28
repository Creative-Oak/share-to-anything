import AppKit
import SendKit
import SendKitUI
import SwiftUI

/// Owns the settings window, so it can be opened from anywhere (menu, URL, first launch)
/// without depending on a SwiftUI scene being alive.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: EndpointStore
    private var window: NSWindow?

    init(store: EndpointStore) {
        self.store = store
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // A menu bar app has no Dock icon; show one while the window is open so it can be Cmd-Tabbed to.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: EndpointListView().environment(store))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        // Don't let SwiftUI push size constraints onto the window while it lays out; that
        // re-enters AppKit layout ("layoutSubtreeIfNeeded on a view which is already being laid out").
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Share to Anything"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 760, height: 500)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
