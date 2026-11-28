import SessionFeature
import SwiftUI
import TerminalUI
import Testing

@MainActor
struct BrowserLinkTests {
    @Test
    func `a link requested before the browser appears takes precedence over its saved page`() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let path = "/repo"
        let savedPage = path + "\tabout:blank#previous\t" + String(Int(Date().timeIntervalSince1970))
        let requested = "about:blank#requested"
        defaults.set(savedPage, forKey: "browserAddresses")
        let keys = [
            UtilityTabTarget.addressKey, UtilityTabTarget.requestKey, UtilityTabTarget.key,
            UtilityTabTarget.visibilityKey,
        ]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        LinkOpener.open(requested, inExternalBrowser: false)
        defaults.set(requested, forKey: UtilityTabTarget.addressKey)
        let host = NSHostingView(rootView: BrowserView(worktreePath: path, isActive: true).defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline, defaults.string(forKey: "browserAddresses")?.contains(requested) != true {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(defaults.string(forKey: "browserAddresses")?.contains(requested) == true)
    }
}
