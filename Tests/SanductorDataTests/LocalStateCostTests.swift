import Foundation
import SanductorData
import Testing

// MARK: - LocalStateCostTests

struct LocalStateCostTests {
    @Test
    func `changed submodule commits refresh an already dirty gitlink`() async throws {
        let path = try TestSupport.temporaryDirectory("local-state-submodule")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let module = path + "/module"
        try await TestSupport.makeRepository(at: module)
        let git = GitClient(runner: FoundationProcessRunner())
        let head = try #require(await git.commitHash(of: "HEAD", worktreePath: module))
        try await TestSupport.runGit(["update-index", "--add", "--cacheinfo", "160000", head, "module"], in: path)
        try await TestSupport.runGit(["commit", "-m", "Track module"], in: path)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "First"], in: module)
        let first = await git.localState(worktreePath: path)

        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Second"], in: module)
        let edited = await git.localState(worktreePath: path)
        #expect(first.isDirty && edited.isDirty)
        #expect(edited.revision != first.revision)
        let current = try #require(await git.commitHash(of: "HEAD", worktreePath: module))
        #expect(try await git.uncommittedDiff(worktreePath: path).contains("+Subproject commit " + current))
    }

    @Test
    func `symlink revisions track the link without following its target`() async throws {
        let root = try TestSupport.temporaryDirectory("local-state-link")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let target = root + "/outside.txt"
        try "first\n".write(toFile: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: path + "/link", withDestinationPath: target)
        let git = GitClient(runner: FoundationProcessRunner())
        let first = await git.localState(worktreePath: path)

        try "other\n".write(toFile: target, atomically: true, encoding: .utf8)
        #expect(await git.localState(worktreePath: path).revision == first.revision)
        try FileManager.default.removeItem(atPath: path + "/link")
        try FileManager.default.createSymbolicLink(atPath: path + "/link", withDestinationPath: root + "/missing")
        #expect(await git.localState(worktreePath: path).revision != first.revision)
    }

    @Test(arguments: ["tracked", "untracked", "binary"])
    func `local revisions detect edits with one status process per reading`(kind: String) async throws {
        let path = try TestSupport.temporaryDirectory("local-state-cost")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let file = kind == "untracked" ? path + "/nested/new file\nname.txt" : path + "/README.md"
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: file).deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        try (kind == "binary" ? Data([0, 1, 2]) : Data("first\n".utf8)).write(to: URL(fileURLWithPath: file))
        let modified = try #require(FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date)
        let runner = LocalStateRunner()
        let git = GitClient(runner: runner)
        let first = await git.localState(worktreePath: path)

        try (kind == "binary" ? Data([0, 1, 3]) : Data("other\n".utf8)).write(to: URL(fileURLWithPath: file))
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file)
        let edited = await git.localState(worktreePath: path)
        #expect(first.isDirty && edited.isDirty)
        #expect(edited.revision != first.revision)
        #expect(await runner.commands.count == 2)
    }
}

// MARK: - LocalStateRunner

private actor LocalStateRunner: ProcessRunner {
    private(set) var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        commands.append(arguments)
        return try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
