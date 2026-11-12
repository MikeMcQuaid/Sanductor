import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct MergedBranchCleanupIntegrationTests {
    @Test(arguments: [false, true])
    func `merge cleanup sweeps unused branches despite stale upstreams`(linked: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: world.root)
        try await TestSupport.runGit(["branch", "stale", "main"], in: origin)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: path)
        for branch in ["master", "trunk"] {
            try await TestSupport.runGit(["branch", branch, "main"], in: path)
        }
        try await TestSupport.runGit(["checkout", "-b", "unmerged", "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Unmerged work"], in: path)
        try await TestSupport.runGit(["checkout", "-b", "topic", "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Merged work"], in: path)
        try await TestSupport.runGit(["branch", "older", "topic"], in: path)
        for branch in ["topic", "older"] {
            try await TestSupport.runGit(["branch", "--set-upstream-to=origin/stale", branch], in: path)
        }
        try await TestSupport.runGit(["worktree", "add", "-b", "held", world.root + "/held", "topic"], in: path)
        try await TestSupport.runGit(["checkout", "main"], in: path)
        try await TestSupport.runGit(["merge", "--ff-only", "topic"], in: path)
        try await TestSupport.runGit(["push", "origin", "main"], in: path)

        let worktree = Worktree(
            repositoryName: world.repository.name,
            repositoryPath: path,
            branch: "topic",
            path: linked ? world.root + "/topic" : path,
        )
        if linked {
            try await TestSupport.runGit(["worktree", "add", worktree.path, "topic"], in: path)
            let item = WorktreeItem(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: 0)
            #expect(try await world.service.cleanUpMergedWorktree(item: item, baseRef: "origin/main") == nil)
            #expect(FileManager.default.fileExists(atPath: worktree.path) == false)
        } else {
            try await TestSupport.runGit(["checkout", "topic"], in: path)
            let report = await world.service.cleanUpAfterMerge(worktree: worktree, mergedBranch: "topic")
            #expect(report.failures.isEmpty, Comment(rawValue: report.failures.joined(separator: "\n")))
        }

        for branch in ["topic", "older"] {
            #expect(await world.service.git.branchExists(repository: world.repository, branch: branch) == false)
        }
        for branch in ["main", "master", "trunk", "held", "unmerged"] {
            #expect(await world.service.git.branchExists(repository: world.repository, branch: branch))
        }
        #expect(await world.service.git.currentBranch(worktreePath: path) == "main")
    }

    @Test
    func `branch cleanup uses the remote default and preserves dirty checkouts and worktrees`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let origin = world.root + "/origin.git"
        try await TestSupport.runGit(["clone", "--bare", path, origin], in: world.root)
        try await TestSupport.runGit(["remote", "add", "origin", origin], in: path)
        try await TestSupport.runGit(["fetch", "origin"], in: path)
        try await TestSupport.runGit(["remote", "set-head", "origin", "--auto"], in: path)
        try await TestSupport.runGit(["checkout", "-b", "merged", "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Merged work"], in: path)
        try await TestSupport.runGit(["push", "origin", "merged:main"], in: path)
        try await TestSupport.runGit(["worktree", "add", "-b", "held", world.root + "/held", "merged"], in: path)
        try await TestSupport.runGit(["checkout", "-b", "unmerged", "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Unmerged work"], in: path)
        try await TestSupport.runGit(["branch", "kept", "unmerged"], in: path)
        try "Local edits".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)

        let cleanup = try await world.service.cleanUpBranches(repository: world.repository)

        #expect(cleanup.deleted == ["merged"])
        #expect(cleanup.failures.isEmpty)
        #expect(await world.service.git.branchExists(repository: world.repository, branch: "merged") == false)
        #expect(await world.service.git.branchExists(repository: world.repository, branch: "kept"))
        #expect(await world.service.git.currentBranch(worktreePath: path) == "unmerged")
        #expect(await world.service.git.currentBranch(worktreePath: world.root + "/held") == "held")
        #expect(await world.service.git.isMerged(worktreePath: path, branch: "origin/main", into: "main") == false)
        #expect(try String(contentsOfFile: path + "/README.md", encoding: .utf8) == "Local edits")
    }
}
