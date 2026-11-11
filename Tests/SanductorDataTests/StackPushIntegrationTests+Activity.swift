import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension StackPushIntegrationTests {
    @Test(arguments: ["push", "fetch"], [false, true])
    func `push rechecks activity after remote operations before integrating a later branch`(
        activityAfter: String, remoteChanged: Bool,
    ) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await publishedPair(in: world, remoteChanged: remoteChanged)
        let path = world.repository.path
        try await TestSupport.runGit(["checkout", "main"], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["worktree", "add", world.root + "/" + branch, branch], in: path)
        }
        let holder = world.root + "/upper"
        try "agent draft".write(toFile: holder + "/draft", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "draft"], in: holder)
        let runner = PushActivityRunner(holder: holder, activityAfter: activityAfter)
        let service = world.service(herdr: world.herdr, git: GitClient(runner: runner))
        let before = await service.git.tip(of: "upper", worktreePath: path)
        let worktree = Worktree(repositoryName: "repo", repositoryPath: path, branch: "upper", path: holder)
        let busy: @Sendable () async -> Set<String> = { runner.state.withLock { $0.busy ? [holder] : [] } }

        if remoteChanged {
            await #expect(throws: SessionServiceError.self) {
                try await service.pushStack(worktree: worktree, busyWorktrees: busy)
            }
        } else {
            #expect(try await service.pushStack(worktree: worktree, busyWorktrees: busy) == ["lower", "upper"])
        }
        #expect(runner.state.withLock { $0.busy })
        #expect(runner.state.withLock { $0.touched } == false)
        #expect(await service.git.tip(of: "upper", worktreePath: path) == before)
        #expect(await service.git.tip(of: "origin/lower", worktreePath: path)
            == service.git.tip(of: "lower", worktreePath: path))
        #expect(try await TestSupport.runGit(["status", "--porcelain"], in: holder).standardOutput == "A  draft\n")
        #expect(try String(contentsOfFile: holder + "/draft", encoding: .utf8) == "agent draft")
    }
}

// MARK: - PushActivityRunner

private final class PushActivityRunner: ProcessRunner {
    // MARK: Lifecycle

    init(holder: String, activityAfter: String) {
        self.holder = holder
        self.activityAfter = activityAfter
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    let state: Mutex = .init((pushedLower: false, busy: false, touched: false))

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if workingDirectory == holder, arguments.contains("stash") || arguments.contains("rebase") {
            state.withLock { $0.touched = true }
        }
        let result = try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
        state.withLock { state in
            if arguments.contains("push") {
                state.pushedLower = true
            }
            if state.pushedLower, arguments.contains(activityAfter) {
                state.busy = true
            }
        }
        return result
    }

    // MARK: Private

    private let holder: String
    private let activityAfter: String
}
