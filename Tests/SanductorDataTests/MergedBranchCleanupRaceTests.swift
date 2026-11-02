import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

// MARK: - MergedBranchCleanupRaceTests

struct MergedBranchCleanupRaceTests {
    @Test
    func `a branch moved after listing keeps its new commits and configuration`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        for branch in ["topic", "older"] {
            try await TestSupport.runGit(["branch", branch, "main"], in: path)
            try await TestSupport.runGit(["config", "branch." + branch + ".description", "Kept"], in: path)
        }
        let tip = try await TestSupport.runGit(
            ["commit-tree", "main^{tree}", "-p", "main", "-m", "Unmerged work"], in: path,
        )
        .standardOutput
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let git = GitClient(runner: CleanupRaceRunner(trigger: "--merged") {
            try await TestSupport.runGit(["update-ref", "refs/heads/topic", tip], in: path)
        })

        let cleanup = try await git.deleteMergedBranches(worktreePath: path, into: "main")
        #expect(cleanup.deleted == ["older"])
        #expect(cleanup.failures.isEmpty)
        #expect(await git.tip(of: "refs/heads/topic", worktreePath: path) == tip)
        #expect(try await git.git(["config", "branch.topic.description"], in: path).standardOutput == "Kept\n")
        #expect(try await git.git(
            ["config", "--get-regexp", #"^branch\.older\."#], in: path, allowFailure: true,
        )
        .status == 1)
    }

    @Test
    func `a branch checked out after listing survives cleanup`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let held = world.root + "/held"
        try await TestSupport.runGit(["branch", "topic", "main"], in: path)
        let git = GitClient(runner: CleanupRaceRunner(trigger: "--merged") {
            try await TestSupport.runGit(["worktree", "add", held, "topic"], in: path)
        })

        let cleanup = try await git.deleteMergedBranches(worktreePath: path, into: "main")
        #expect(cleanup.deleted.isEmpty)
        #expect(cleanup.failures.isEmpty)
        #expect(await git.branchExists(repository: world.repository, branch: "topic"))
        #expect(await git.currentBranch(worktreePath: held) == "topic")
    }

    @Test(arguments: ["merge-base", "prune"])
    func `worktree cleanup preserves a branch moved after its ancestry check`(trigger: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = Worktree(
            repositoryName: world.repository.name, repositoryPath: path, branch: "topic", path: world.root + "/topic",
        )
        try await TestSupport.runGit(["worktree", "add", "-b", "topic", worktree.path, "main"], in: path)
        let tip = try await TestSupport.runGit(
            ["commit-tree", "main^{tree}", "-p", "main", "-m", "Unmerged work"], in: path,
        )
        .standardOutput
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let git = GitClient(runner: CleanupRaceRunner(trigger: trigger) {
            try await TestSupport.runGit(["update-ref", "refs/heads/topic", tip], in: path)
        })
        let service = world.service(herdr: world.herdr, git: git)
        let item = WorktreeItem(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: 0)

        #expect(try await service.cleanUpMergedWorktree(item: item, baseRef: "main") == nil)
        #expect(FileManager.default.fileExists(atPath: worktree.path) == false)
        #expect(await git.tip(of: "refs/heads/topic", worktreePath: path) == tip)
    }

    @Test(arguments: ["prune", "--merged"])
    func `cleanup preserves a branch when its base was rewound during removal`(trigger: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = Worktree(
            repositoryName: world.repository.name, repositoryPath: path, branch: "topic", path: world.root + "/topic",
        )
        try await TestSupport.runGit(["worktree", "add", "-b", "topic", worktree.path, "main"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Merged work"], in: worktree.path)
        try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "topic"], in: path)
        let git = GitClient(runner: CleanupRaceRunner(trigger: trigger) {
            try await TestSupport.runGit(["update-ref", "refs/remotes/origin/main", "main"], in: path)
        })
        let service = world.service(herdr: world.herdr, git: git)
        let item = WorktreeItem(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: 0)

        #expect(try await service.cleanUpMergedWorktree(item: item, baseRef: "origin/main") == nil)
        #expect(FileManager.default.fileExists(atPath: worktree.path) == false)
        #expect(await git.branchExists(repository: world.repository, branch: "topic"))
    }

    @Test(arguments: ["refs/heads/older.lock", "config.lock"])
    func `cleanup reports write failures and continues with other branches`(lock: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let worktree = Worktree(
            repositoryName: world.repository.name,
            repositoryPath: path,
            branch: "removed",
            path: world.root + "/removed",
        )
        try await TestSupport.runGit(["worktree", "add", "-b", "removed", worktree.path, "main"], in: path)
        for branch in ["older", "topic"] {
            try await TestSupport.runGit(["branch", branch, "main"], in: path)
            try await TestSupport.runGit(["config", "branch." + branch + ".description", "Kept"], in: path)
        }
        try Data().write(to: URL(fileURLWithPath: path + "/.git/" + lock))
        let failures = Mutex<[String]>([])
        let item = WorktreeItem(worktree: worktree, session: nil, isDirty: false, aheadOfUpstream: 0)

        let refusal = try await world.service.cleanUpMergedWorktree(item: item, baseRef: "main") { message in
            failures.withLock { $0.append(message) }
        }
        #expect(refusal == nil)
        #expect(failures.withLock { $0 }.contains { $0.contains("older") && $0.contains("lock") })
        #expect(FileManager.default.fileExists(atPath: worktree.path) == false)
        #expect(await world.service.git.branchExists(repository: world.repository, branch: "topic") == false)
        #expect(await world.service.git.branchExists(repository: world.repository, branch: "older")
            == (lock == "refs/heads/older.lock"))
    }
}

// MARK: - CleanupRaceRunner

private actor CleanupRaceRunner: ProcessRunner {
    // MARK: Lifecycle

    init(trigger: String, action: @escaping @Sendable () async throws -> Void) {
        self.trigger = trigger
        self.action = action
    }

    // MARK: Internal

    let trigger: String
    let action: @Sendable () async throws -> Void

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        let result = try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
        if triggered == false, arguments.contains(trigger), result.succeeded {
            triggered = true
            try await action()
        }
        return result
    }

    // MARK: Private

    private var triggered = false
}
