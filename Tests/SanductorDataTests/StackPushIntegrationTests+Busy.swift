import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension StackPushIntegrationTests {
    @Test(arguments: ["lower", "upper"], [false, true])
    func `push only refuses busy holders when integration needs a rebase`(
        busyBranch: String, remoteChanged: Bool,
    ) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try await publishedPair(in: world, remoteChanged: remoteChanged)
        let path = world.repository.path
        let holder = world.root + "/" + busyBranch
        try await TestSupport.runGit(["checkout", "main"], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["worktree", "add", world.root + "/" + branch, branch], in: path)
        }
        let link = world.root + "/holder-link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: holder)
        try "agent draft".write(toFile: holder + "/draft", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "draft"], in: holder)
        let before = await world.service.git.tip(of: busyBranch, worktreePath: path)
        let status = try await TestSupport.runGit(["status", "--porcelain"], in: holder).standardOutput
        let worktree = Worktree(
            repositoryName: "repo", repositoryPath: path, branch: "upper", path: world.root + "/upper",
        )
        let busy: @Sendable () async -> Set<String> = { [link] }

        if remoteChanged {
            await #expect(throws: SessionServiceError.self) {
                try await world.service.pushStack(worktree: worktree, busyWorktrees: busy)
            }
        } else {
            #expect(try await world.service.pushStack(worktree: worktree, busyWorktrees: busy) == ["lower", "upper"])
            #expect(await world.service.git.tip(of: "origin/lower", worktreePath: path)
                == world.service.git.tip(of: "lower", worktreePath: path))
        }
        #expect(await world.service.git.tip(of: busyBranch, worktreePath: path) == before)
        #expect(try await TestSupport.runGit(["status", "--porcelain"], in: holder).standardOutput == status)
        #expect(try String(contentsOfFile: holder + "/draft", encoding: .utf8) == "agent draft")
        #expect(await world.service.git.currentBranch(worktreePath: holder) == busyBranch)
        #expect(try await TestSupport.runGit(["stash", "list"], in: path).standardOutput.isEmpty)
    }

    func publishedPair(in world: World, remoteChanged: Bool) async throws {
        let path = world.repository.path
        try await BranchStackIntegrationTests.signable(path)
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "main"], in: path)
        for branch in ["lower", "upper"] {
            try await TestSupport.runGit(["checkout", "-b", branch], in: path)
            try await TestSupport.runGit(["commit", "-S", "--allow-empty", "-m", branch], in: path)
            try await TestSupport.runGit(["push", "--set-upstream", "origin", branch], in: path)
            if branch == "lower" {
                try await TestSupport.runGit(["commit", "-S", "--allow-empty", "-m", "Local work"], in: path)
            }
        }
        if remoteChanged {
            let elsewhere = world.root + "/elsewhere"
            try await TestSupport.runGit(["clone", "--branch", "lower", origin, elsewhere], in: path)
            try "remote work".write(toFile: elsewhere + "/remote", atomically: true, encoding: .utf8)
            try await TestSupport.runGit(["add", "remote"], in: elsewhere)
            try await TestSupport.runGit(
                ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Remote work"],
                in: elsewhere,
            )
            try await TestSupport.runGit(["push", "origin", "lower"], in: elsewhere)
        }
    }
}
