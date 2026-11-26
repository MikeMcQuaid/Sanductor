import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

// MARK: - RebasedBranchPushIntegrationTests

struct RebasedBranchPushIntegrationTests {
    @Test
    @MainActor
    func `a slow push allows local reads and a push in another repository`() async throws {
        let root = try TestSupport.temporaryDirectory("slow-push")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let first = root + "/first"
        let second = root + "/second"
        for path in [first, second] {
            try await TestSupport.makeRepository(at: path)
            try await TestSupport.runGit(["init", "--bare", path + ".git"], in: root)
            try await TestSupport.runGit(["remote", "add", "origin", path + ".git"], in: path)
        }
        let git = GitClient(runner: DelayedPushRunner(path: first))
        async let push: Void = git.push(worktreePath: first, branch: "main")
        try #require(await TestSupport.poll { FileManager.default.fileExists(atPath: first + "/waiting") })
        #expect(await git.localState(worktreePath: first).isDirty)
        try await git.push(worktreePath: second, branch: "main")
        try "".write(toFile: first + "/release", atomically: false, encoding: .utf8)
        try await push
    }

    @Test
    func `a known remote tip needs only the leased push`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: path)
        try await TestSupport.runGit(["push", "--set-upstream", "origin", "feature"], in: path)
        try await BranchStackIntegrationTests.commit("update", in: path)
        try await TestSupport.runGit(["remote", "set-url", "--push", "origin", origin], in: path)
        try await TestSupport.runGit(["remote", "set-url", "origin", world.root + "/missing.git"], in: path)
        let config = path + "/.git/config"
        let timestamp = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: config)
        try await world.service.git.push(worktreePath: path, branch: "feature")
        #expect(try FileManager.default.attributesOfItem(atPath: config)[.modificationDate] as? Date == timestamp)
        #expect(try await BranchStackIntegrationTests.tip(of: "feature", in: origin)
            == BranchStackIntegrationTests.tip(of: "feature", in: path))
    }

    @Test
    func `a stale tracking lease fetches and integrates the remote change before retrying`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        let other = world.root + "/other"
        try await BranchStackIntegrationTests.signable(path)
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: path)
        try await TestSupport.runGit(["push", "--set-upstream", "origin", "feature"], in: path)
        try await TestSupport.runGit(["clone", "--branch", "feature", origin, other], in: path)
        try await BranchStackIntegrationTests.commit("external", in: other)
        try await TestSupport.runGit(["push", "origin", "feature"], in: other)
        try await BranchStackIntegrationTests.commit("local", in: path)
        try await world.service.git.push(worktreePath: path, branch: "feature")
        let files = try await TestSupport.runGit(["ls-tree", "--name-only", "feature"], in: origin).standardOutput
        #expect(files.contains("external.txt"))
        #expect(files.contains("local.txt"))
    }

    @Test(arguments: ["main", "parent"], ["origin", "contributor"])
    func `pushing a rebased branch preserves unknown remote commits`(base: String, remote: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        let publisher = world.root + "/publisher"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        if remote != "origin" {
            try await TestSupport.runGit(["remote", "add", remote, origin], in: path)
        }
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        try await TestSupport.runGit(["clone", origin, publisher], in: path)
        try await TestSupport.runGit(["checkout", "-b", "feature", "main"], in: publisher)
        try "old version\n".write(toFile: publisher + "/README.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-am", "Feature"], in: publisher,
        )
        try await TestSupport.runGit(["push", "origin", "feature"], in: publisher)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        if base != "main" {
            try await TestSupport.runGit(["checkout", "-b", base, "main"], in: path)
        }
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "New parent"], in: path)
        try await TestSupport.runGit(["push", "origin", base], in: path)
        try await TestSupport.runGit(["checkout", "-b", "feature", base], in: path)
        try "updated version\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await BranchStackIntegrationTests.signable(path)
        try await TestSupport.runGit(["commit", "-S", "-am", "Feature, updated"], in: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let tip = try #require(await git.tip(of: "feature", worktreePath: path))
        let remoteTip = try #require(await git.tip(of: "feature", worktreePath: origin))
        let parent = try #require(await git.tip(of: base, worktreePath: path))
        #expect(await git.refWasBranchTip(worktreePath: path, branch: "feature", ref: "origin/feature") == false)

        await #expect(throws: SessionServiceError.self) {
            try await git.push(
                worktreePath: path,
                branch: "feature",
                remote: remote,
                parent: base == "main" ? nil : (base, parent),
            )
        }

        #expect(await git.tip(of: "feature", worktreePath: path) == tip)
        #expect(await git.tip(of: "feature", worktreePath: origin) == remoteTip)
        #expect(await git.commitCount(worktreePath: path, range: base + "..feature") == 1)
    }
}

// MARK: - DelayedPushRunner

/// Holds the network stage in a subprocess until the main actor finishes its independent work.
private struct DelayedPushRunner: ProcessRunner {
    let path: String

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        let runner = FoundationProcessRunner()
        if workingDirectory == path, arguments.contains("push") {
            let delay = """
            touch waiting
            for ((i=0; i<200; i++)); do
              [[ -f release ]] && exit 0
              sleep 0.05
            done
            exit 1
            """
            let waited = try await runner.run(["/bin/bash", "-c", delay], workingDirectory: path, environment: [:])
            guard waited.succeeded else {
                return waited
            }
        }
        return try await runner.run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
