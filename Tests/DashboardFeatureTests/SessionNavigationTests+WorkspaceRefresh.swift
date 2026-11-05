import AppKit
@testable import DashboardFeature
import Foundation
import Testing

@MainActor
extension SessionNavigationTests {
    @Test(arguments: ["mains", "battery", "hidden", "loading"])
    func `filesystem events refresh only a loaded visible window on mains power`(
        state: String,
    ) async throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        let model = fixture.model
        defer { fixture.close() }
        try FileManager.default.createDirectory(atPath: fixture.repository.path, withIntermediateDirectories: true)
        model.watcher.start()
        try #require(model.watcher.isWatching)
        try await Task.sleep(for: .seconds(2))
        _ = model.watcher.consumeChangedPaths()

        let blocked = Task {
            _ = try? await Task.sleep(for: .seconds(30))
        }
        defer { blocked.cancel() }
        model.refreshTask = blocked
        model.pendingPaneRead = false
        model.isOnBattery = { state == "battery" }
        model.isWindowVisible = state != "hidden"
        model.hasLoaded = state != "loading"
        try "changed\n".write(
            toFile: fixture.repository.path + "/changed.txt", atomically: true, encoding: .utf8,
        )

        let immediate = state == "mains"
        let deadline = ContinuousClock.now + .seconds(12)
        var changed = Set<String>()
        while ContinuousClock.now < deadline {
            changed.formUnion(model.watcher.consumeChangedPaths())
            if changed.isEmpty == false, immediate == false || model.queuedRefresh != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(changed.isEmpty == false)
        #expect((model.queuedRefresh != nil) == immediate)
        #expect(model.pendingPaneRead == false)

        model.hasLoaded = false
        blocked.cancel()
        await model.queuedRefresh?.value
    }
}
