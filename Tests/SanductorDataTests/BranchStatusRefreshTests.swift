import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct BranchStatusRefreshTests {
    // MARK: Internal

    @Test(arguments: ["sha1", "sha256"])
    func `unborn revisions include untracked content and preserve staged work`(format: String) async throws {
        let path = try TestSupport.temporaryDirectory("unborn-revision")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.runGit(["init", "-q", "-b", "main", "--object-format=" + format], in: path)
        try "staged\n".write(toFile: path + "/staged.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "staged.txt"], in: path)
        try "first\n".write(toFile: path + "/new.txt", atomically: true, encoding: .utf8)
        let indexURL = URL(fileURLWithPath: path + "/.git/index")
        let index = try Data(contentsOf: indexURL)
        let git = GitClient(runner: FoundationProcessRunner())
        let first = await git.localState(worktreePath: path)
        try "other\n".write(toFile: path + "/new.txt", atomically: true, encoding: .utf8)
        let edited = await git.localState(worktreePath: path)

        #expect(first.isDirty && edited.isDirty)
        #expect(edited.revision != first.revision)
        #expect(await git.localState(worktreePath: path).revision == edited.revision)
        let files = try await DiffParser.parse(git.uncommittedDiff(worktreePath: path))
        #expect(files.map(\.path) == ["new.txt", "staged.txt"])
        #expect(files.first?.hunks.first?.lines.contains { $0.content == "other" } == true)
        #expect(try Data(contentsOf: indexURL) == index)
    }

    @Test(arguments: ["refs/heads/main", "refs/remotes/origin/main"])
    func `host revisions follow shared default refs without moving HEAD`(ref: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.root + "/host"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["checkout", "-b", "feature"], in: path)
        try "feature\n".write(toFile: path + "/feature.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "feature.txt"], in: path)
        try await TestSupport.runGit(["commit", "-m", "Feature"], in: path)
        try await TestSupport.runGit(["update-ref", ref, "HEAD^"], in: path)
        var service = world.service
        service.selectedWorktreePath = { path }
        service.addHostDirectory(path, to: world.repository)
        let metadata = service.store.load()
        let first = try #require(await service.hostItems(of: world.repository, metadata: metadata).first)
        #expect(try await service.git.branchDiff(worktreePath: path, baseRef: ref).contains("+feature"))

        try await TestSupport.runGit(["update-ref", ref, "HEAD"], in: path)
        let updated = try #require(await service.hostItems(of: world.repository, metadata: metadata).first)
        #expect(updated.isDirty == first.isDirty)
        #expect(updated.aheadOfUpstream == first.aheadOfUpstream)
        #expect(updated.branchStatus != first.branchStatus)
        #expect(try await service.git.branchDiff(worktreePath: path, baseRef: ref).isEmpty)
        #expect(
            await service.hostItems(of: world.repository, metadata: metadata).first?.branchStatus
                == updated.branchStatus,
        )
    }

    @Test(arguments: ["tracked", "staged", "untracked"])
    func `further edits refresh a dirty worktree without idle churn`(kind: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.root + "/worktree"
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", path], in: world.repository.path)
        let file = kind == "untracked" ? "new file\nname.txt" : "README.md"
        try "first\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        if kind == "staged" {
            try await TestSupport.runGit(["add", "--", file], in: path)
        }
        let first = try await item(in: world, at: path)
        #expect(first.isDirty)
        #expect(try await item(in: world, at: path).branchStatus == first.branchStatus)

        try "other\n".write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        if kind == "staged" {
            try await TestSupport.runGit(["add", "--", file], in: path)
        }
        let edited = try await item(in: world, at: path)
        #expect(edited.isDirty)
        #expect(edited.branchStatus != first.branchStatus)
        #expect(try await item(in: world, at: path).branchStatus == edited.branchStatus)

        try "ignored.txt\n".write(
            toFile: world.repository.path + "/.git/info/exclude", atomically: true, encoding: .utf8,
        )
        try "ignored\n".write(toFile: path + "/ignored.txt", atomically: true, encoding: .utf8)
        #expect(try await item(in: world, at: path).branchStatus == edited.branchStatus)
    }

    @Test(arguments: [false, true])
    func `rewriting the tip refreshes commit views even while detached`(detached: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.root + "/feature"
        try await TestSupport.runGit(["worktree", "add", "-b", "feature", path], in: world.repository.path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Feature"], in: path)
        if detached {
            try await TestSupport.runGit(["checkout", "--detach", "HEAD"], in: path)
        }
        let first = try await item(in: world, at: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "--amend", "-m", "Amended message"], in: path)
        let amended = try await item(in: world, at: path)
        #expect(amended.isDirty == false)
        #expect(amended.aheadOfDefault == first.aheadOfDefault)
        #expect(amended.branchStatus != first.branchStatus)
        #expect(try await item(in: world, at: path).branchStatus == amended.branchStatus)
    }

    @Test(arguments: [false, true])
    func `host directory git views refresh edits and amendments`(amend: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.root + "/host"
        try await TestSupport.makeRepository(at: path)
        var service = world.service
        service.selectedWorktreePath = { path }
        service.addHostDirectory(path, to: world.repository)
        if amend == false {
            try "first\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        }
        let metadata = service.store.load()
        let first = try #require(await service.hostItems(of: world.repository, metadata: metadata).first)
        if amend {
            try await TestSupport.runGit(["commit", "--amend", "-m", "Amended"], in: path)
        } else {
            try "other\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        }
        let updated = try #require(await service.hostItems(of: world.repository, metadata: metadata).first)
        #expect(updated.isDirty == first.isDirty)
        #expect(updated.branchStatus != first.branchStatus)
    }

    // MARK: Private

    private func item(in world: World, at path: String) async throws -> WorktreeItem {
        let group = await world.service.group(of: world.repository, panes: [], activity: [:], metadata: AppMetadata())
        return try #require(group.items.first { $0.worktree.path == path })
    }
}
