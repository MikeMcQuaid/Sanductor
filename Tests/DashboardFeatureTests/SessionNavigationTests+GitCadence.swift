@testable import DashboardFeature
import Foundation
import SanductorDomain
import Synchronization
import Testing

@MainActor
extension SessionNavigationTests {
    @Test(arguments: [true, false])
    func `filesystem changes select the exact worktree or sibling repository`(inWorktree: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        let repository = fixture.repository
        let worktree = Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: "task",
            path: fixture.root + "/shared/worktrees/repo/task",
        )
        model.groups[0].items.append(.init(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: nil))
        let directory = (inWorktree ? worktree.path : repository.path + ".sh") + "/src"
        model.isOnBattery = { false }
        model.isWindowVisible = true
        try await writeFile(in: directory, fixture: fixture)
        let scope = model.gitReadScope(forcing: [])
        #expect(scope.includes(worktree.path) == inWorktree)
        #expect(scope.includes(repository.path) == false)
    }

    @Test(arguments: ["battery", "hidden", "mains"])
    func `automatic git readings retain changes until the slower cadence allows them`(state: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        model.isOnBattery = { state == "battery" }
        model.isWindowVisible = state != "hidden"
        try await writeFile(in: fixture.repository.path, fixture: fixture)
        #expect(model.gitReadScope(forcing: []).includes(fixture.repository.path) == (state == "mains"))

        if state != "mains" {
            let interval = RefreshCadence.pollSeconds(
                setting: DashboardModel.pollInterval, visible: model.isWindowVisible, onBattery: model.isOnBattery(),
            )
            model.lastGitReadAt = Date().addingTimeInterval(-Double(interval) - 1)
            #expect(model.gitReadScope(forcing: []).includes(fixture.repository.path))
        }
        #expect(model.gitReadScope(forcing: [fixture.repository.path]).includes(fixture.repository.path))
    }

    private func writeFile(in directory: String, fixture: Fixture) async throws {
        let model = fixture.model
        let changed = Mutex(false)
        model.watcher.onChange { changed.withLock { $0 = true } }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        model.watcher.start()
        try #require(model.watcher.isWatching)
        let settleSeconds = 2
        try await Task.sleep(for: .seconds(settleSeconds))
        _ = model.watcher.consumeChangedPaths()
        changed.withLock { $0 = false }
        model.hasLoaded = true
        model.lastGitReadAt = Date()
        model.gitReadAt[fixture.repository.path] = model.lastGitReadAt
        try "edit".write(toFile: directory + "/changed.txt", atomically: false, encoding: .utf8)
        let timeoutSeconds = 12
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        let pollMilliseconds = 50
        while changed.withLock({ $0 }) == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(pollMilliseconds))
        }
        try #require(changed.withLock { $0 })
    }
}
