@testable import DashboardFeature
import Foundation
import SanductorDomain
import Synchronization
import Testing

@MainActor
extension SessionNavigationTests {
    @Test(arguments: ["battery", "hidden", "mains"])
    func `automatic git readings retain changes until the slower cadence allows them`(state: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        try FileManager.default.createDirectory(atPath: fixture.repository.path, withIntermediateDirectories: true)
        model.watcher.start()
        try #require(model.watcher.isWatching)
        try await Task.sleep(for: .seconds(2))
        _ = model.watcher.consumeChangedPaths()
        let changed = Mutex(false)
        model.watcher.onChange { changed.withLock { $0 = true } }
        model.isOnBattery = { state == "battery" }
        model.isWindowVisible = state != "hidden"
        model.hasLoaded = true
        model.gitReadAt[fixture.repository.path] = Date()
        try "changed\n".write(
            toFile: fixture.repository.path + "/changed.txt", atomically: true, encoding: .utf8,
        )
        let deadline = ContinuousClock.now + .seconds(12)
        while changed.withLock({ $0 }) == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(changed.withLock { $0 })
        #expect(model.gitReadScope(forcing: []).includes(fixture.repository.path) == (state == "mains"))

        if state != "mains" {
            let interval = RefreshCadence.pollSeconds(
                setting: DashboardModel.pollInterval, visible: model.isWindowVisible, onBattery: model.isOnBattery(),
            )
            model.gitReadAt[fixture.repository.path] = Date().addingTimeInterval(-Double(interval) - 1)
            #expect(model.gitReadScope(forcing: []).includes(fixture.repository.path))
        }
        #expect(model.gitReadScope(forcing: [fixture.repository.path]).includes(fixture.repository.path))
    }
}
