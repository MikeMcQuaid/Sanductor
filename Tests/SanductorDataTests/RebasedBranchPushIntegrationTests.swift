import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct RebasedBranchPushIntegrationTests {
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
