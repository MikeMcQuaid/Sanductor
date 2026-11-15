import Foundation
import SanductorData
import SanductorDomain
import Testing

struct BranchRecencyTests {
    @Test
    func `only a repository checkout can switch to its default branch`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repository = try #require(world.service.repositories().first)
        try await TestSupport.runGit(["checkout", "-b", "host", "main"], in: repository.path)
        let path = world.root + "/linked"
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", path, "main"], in: repository.path)
        let linked = Worktree(
            repositoryName: repository.name, repositoryPath: repository.path, branch: "feature", path: path,
        )
        #expect(await world.service.availableBranches(worktree: linked).isEmpty)
        await #expect(throws: (any Error).self) {
            try await world.service.switchBranch("main", worktree: linked)
        }
        let main = Worktree(
            repositoryName: repository.name, repositoryPath: repository.path, branch: "host", path: repository.path,
        )
        #expect(await world.service.availableBranches(worktree: main) == ["main"])
        let group = RepositoryGroup(
            repository: repository,
            items: [main, linked].map { worktree in
                WorktreeItem(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: nil)
            },
            defaultBranch: "main",
            localBranches: ["main", "host", "feature"],
        )
        #expect(group.canSwitchBranch(in: linked))
        #expect(group.canSwitchBranch(in: main))
    }

    @Test
    func `branch switching lists the newest tip before older branches`() async throws {
        let path = try TestSupport.temporaryDirectory("branch-recency")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let runner = FoundationProcessRunner()
        for (branch, date) in [("older", "2020-01-01T00:00:00Z"), ("newer", "2021-01-01T00:00:00Z")] {
            _ = try await TestSupport.run(["git", "checkout", "-b", branch, "main"], in: path)
            _ = try await runner.run(
                ["git", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", branch],
                workingDirectory: path,
                environment: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date],
            )
        }
        let branches = await GitClient(runner: runner).branches(worktreePath: path, newestFirst: true)
        #expect(branches.filter { $0 != "main" } == ["newer", "older"])
    }
}
