import AppKit
import Foundation

// MARK: - 应用图标提供器 (线程安全)
actor AppIconProvider {
    static let shared = AppIconProvider()
    private var cache: [String: NSImage] = [:]

    private init() {}

    func icon(for bundleID: String?) -> NSImage? {
        guard
            let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }

        if let cached = cache[bundleID] { return cached }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 18, height: 18)
        cache[bundleID] = icon
        return icon
    }

    func clearCache() {
        cache.removeAll()
    }
}
