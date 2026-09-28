import Foundation

/// Identifiers injected through each target's Info.plist, so the team prefix is resolved at build time.
public enum AppConfig {
    public static let urlScheme = "sharetoanything"

    public static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    public static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    }

    /// Shared container for app + extensions. Falls back to Application Support (tests, unsigned builds).
    public static var containerURL: URL {
        if let id = appGroupID,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        let fallback = URL.applicationSupportDirectory.appending(path: "ShareToAnything", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Where extensions put copies of shared items before handing them to the app.
    public static var outboxURL: URL {
        let url = containerURL.appending(path: "Outbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
