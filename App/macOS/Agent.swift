import Foundation
import Observation
import SendKit
import SendKitUI
import UserNotifications

/// Performs sends requested by the Finder Sync and Share extensions via
/// `sharetoanything://send?endpoint=<uuid>&file=<path>&file=<path>[&cleanup=1]`.
@MainActor
@Observable
final class Agent: NSObject, UNUserNotificationCenterDelegate {
    private(set) var history: [SendRecord] = SendHistory.load()
    private(set) var activeSends = 0

    @ObservationIgnored private let store: EndpointStore

    init(store: EndpointStore) {
        self.store = store
    }

    func handle(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme, url.host == "send",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }

        let files = items.filter { $0.name == "file" }.compactMap(\.value).map { SharedFile(url: URL(fileURLWithPath: $0)) }
        let cleanup = items.contains { $0.name == "cleanup" && $0.value == "1" }
        store.reload()
        guard let id = items.first(where: { $0.name == "endpoint" })?.value.flatMap(UUID.init),
              let endpoint = store.endpoint(id: id) else {
            finish(SendRecord(endpointName: "Unknown endpoint", files: files.map(\.filename), success: false,
                              message: "That endpoint no longer exists."))
            return
        }
        Task { await send(files, to: endpoint, cleanup: cleanup) }
    }

    func send(_ files: [SharedFile], to endpoint: Endpoint, cleanup: Bool) async {
        activeSends += 1
        defer { activeSends -= 1 }

        var cleanupDelay: Duration = .zero
        let names = files.map(\.filename)
        do {
            if let folder = files.first(where: { $0.url.hasDirectoryPath || isDirectory($0.url) }) {
                throw SendError("\(folder.filename) is a folder. Select files instead.")
            }
            switch try await Sender().send(files, to: endpoint) {
            case .sent(let message):
                finish(SendRecord(endpointName: endpoint.name, files: names, success: true, message: message))
            case .draft(let draft):
                try MailComposer.present(draft)
                // Mail reads the attachments asynchronously, so keep temporary copies around for a while.
                cleanupDelay = .seconds(120)
                history.insert(SendRecord(endpointName: endpoint.name, files: names, success: true, message: "Draft opened in Mail"), at: 0)
                SendHistory.append(history[0])
            }
        } catch {
            finish(SendRecord(endpointName: endpoint.name, files: names, success: false, message: error.localizedDescription))
        }

        if cleanup {
            try? await Task.sleep(for: cleanupDelay)
            removeOutboxCopies(files)
        }
    }

    private func finish(_ record: SendRecord) {
        SendHistory.append(record)
        history.insert(record, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        notify(record)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// Deletes the per-request folders the share extension created in the Outbox.
    private func removeOutboxCopies(_ files: [SharedFile]) {
        let outbox = AppConfig.outboxURL.standardizedFileURL.path
        for folder in Set(files.map { $0.url.deletingLastPathComponent().standardizedFileURL }) where folder.path.hasPrefix(outbox + "/") {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ record: SendRecord) {
        let content = UNMutableNotificationContent()
        content.title = record.success ? "Sent to \(record.endpointName)" : "Couldn't send to \(record.endpointName)"
        content.body = record.message
        if !record.success { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
