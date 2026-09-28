import FinderSync
import SendKit
import ServiceManagement
import SwiftUI

/// The native menu shown from the menu bar icon.
struct MenuBarContent: View {
    var agent: Agent
    var openSettings: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if agent.activeSends > 0 {
            Text("Sending \(agent.activeSends) …")
            Divider()
        }

        Section("Recent") {
            if agent.history.isEmpty {
                Text("Right-click a file in Finder and choose Send to")
            }
            ForEach(agent.history.prefix(8)) { record in
                Button(action: openSettings) {
                    Label(record.files.joined(separator: ", "),
                          systemImage: record.success ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(record.success
                         ? "\(record.endpointName) · \(record.date.formatted(.relative(presentation: .named)))"
                         : record.message)
                }
            }
        }

        Divider()

        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Button("Enable Finder Extension…") {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }

        Divider()

        Button("Quit Share to Anything") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
