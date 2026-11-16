import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

/// Which worktrees reach the sidebar: those a person or Sanductor
/// made, wherever their checkout lists them, but never the build
/// worktrees Claude Code and Codex make for themselves.
struct StrayWorktreeTests {
    @Test
    func `a stray worktree from a foreign base clone is listed`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let container = world.paths.worktreesDirectory + "/repo"
        let base = container + "/.base"
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        try await TestSupport.runGit(["clone", "-q", world.repository.path, base], in: world.root)
        try await TestSupport.runGit(
            ["worktree", "add", "-q", "-b", "stray_work", container + "/stray_work"],
            in: base,
        )

        let overview = await world.service.overview()
        let item = overview.groups.first?.items.first { $0.worktree.branch == "stray_work" }
        #expect(item != nil)
        #expect(item?.worktree.path == container + "/stray_work")
        // Branch work and deletion must land on the owning clone,
        // not the canonical checkout that never heard of the branch.
        #expect(item?.worktree.repositoryPath == base)
    }

    @Test
    func `agent tools' own worktrees are not listed`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let paths = [
            world.root + "/home/.codex/worktrees/9868/repo",
            world.repository.path + "/.claude/worktrees/build",
            world.root + "/elsewhere/by_hand",
        ]
        for (index, path) in paths.enumerated() {
            try await TestSupport.runGit(
                ["worktree", "add", "-q", "-b", "work_" + String(index), path],
                in: world.repository.path,
            )
        }

        let overview = await world.service.overview()
        let listed = Set(overview.groups.first?.items.map(\.worktree.path) ?? [])
        #expect(listed.contains(paths[0]) == false)
        #expect(listed.contains(paths[1]) == false)
        #expect(listed.contains(paths[2]))
    }
}
