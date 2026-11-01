import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

// MARK: - GitRemoteRenameTests

struct GitRemoteRenameTests {
    @Test(arguments: ["https://github.com/", "git@github.com:"], [false, true])
    func `fetch notices repair the remote and invalidate its name`(prefix: String, failed: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("rename")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.runGit(["init", "-q", root], in: root)
        try await TestSupport.runGit(["remote", "add", "origin", prefix + "owner/Old.git"], in: root)
        try await TestSupport.runGit(["remote", "add", "fork", prefix + "other/Old.git"], in: root)
        let notice = prefix.hasPrefix("https")
            ? "warning: redirecting to https://github.com/owner/New.git/\n"
            : "remote: This repository moved. Please use the new location:\nremote:   git@github.com:owner/New.git\n"
        let client = GitClient(runner: RenameRunner(notice: notice, failed: failed)) { true }
        let repository = Repository(name: "checkout", path: root)
        #expect(await client.fullName(of: repository) == "owner/Old")
        _ = try? await client.preparePush(worktreePath: root, branch: "main", remote: "origin")
        #expect(
            await client.remoteURL(named: "origin", worktreePath: root)
                == prefix + (failed ? "owner/Old.git" : "owner/New.git"),
        )
        #expect(await client.remoteURL(named: "fork", worktreePath: root) == prefix + "other/Old.git")
        #expect(await client.fullName(of: repository) == (failed ? "owner/Old" : "owner/New"))
    }

    @Test(arguments: [false, true])
    func `submodule redirects never replace the selected remote`(parentMoved: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("submodule-rename")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.runGit(["init", "-q", root], in: root)
        try await TestSupport.runGit(["remote", "add", "origin", "https://github.com/owner/Old.git"], in: root)
        let client = GitClient(runner: RenameRunner(
            notice: "Fetching submodule vendor/dependency\n"
                + "warning: redirecting to https://github.com/dependency/New.git/\n",
            failed: false,
            confirmation: parentMoved ? "warning: redirecting to https://github.com/owner/New.git/\n" : "",
        )) { true }
        _ = try await client.preparePush(worktreePath: root, branch: "main", remote: "origin")
        #expect(await client.remoteURL(named: "origin", worktreePath: root)
            == "https://github.com/owner/" + (parentMoved ? "New.git" : "Old.git"))
    }

    @Test(arguments: [false, true])
    func `push notices preserve an unrelated fetch URL and remote ownership`(separatePush: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("rename")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.runGit(["init", "-q", root], in: root)
        let fetch = "https://github.com/" + (separatePush ? "upstream/Other.git" : "owner/Old.git")
        try await TestSupport.runGit(["remote", "add", "fork", fetch], in: root)
        try await TestSupport.runGit(["config", "remote.fork.pushurl", "git@github.com:owner/Old.git"], in: root)
        try await TestSupport.runGit(["config", "remote.fork.sanductor-created-url", fetch], in: root)
        let client = GitClient(runner: RenameRunner(
            notice: "remote: This repository moved. Please use the new location:\n"
                + "remote:   git@github.com:owner/New.git\n",
            failed: false,
        )) { true }
        try await client.git(["push", "fork", "main"], in: root, remote: "fork")
        let expectedFetch = separatePush ? fetch : "https://github.com/owner/New.git"
        #expect(await client.remoteURL(named: "fork", worktreePath: root) == expectedFetch)
        #expect(
            await client.remoteURL(named: "fork", worktreePath: root, forPush: true) == "git@github.com:owner/New.git",
        )
        let marker = try await TestSupport.runGit(["config", "remote.fork.sanductor-created-url"], in: root)
        #expect(marker.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == expectedFetch)
    }

    @Test(arguments: ["https://evil.example/owner/New.git", "https://github.com/owner/New.git;touch /bad"])
    func `untrusted redirect destinations leave remotes alone`(destination: String) async throws {
        let root = try TestSupport.temporaryDirectory("rename")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await TestSupport.runGit(["init", "-q", root], in: root)
        try await TestSupport.runGit(["remote", "add", "origin", "https://github.com/owner/Old.git"], in: root)
        let client = GitClient(runner: RenameRunner(
            notice: "warning: redirecting to " + destination, failed: false,
        )) { true }
        _ = try await client.preparePush(worktreePath: root, branch: "main", remote: "origin")
        #expect(await client.remoteURL(named: "origin", worktreePath: root) == "https://github.com/owner/Old.git")
    }
}

// MARK: - RenameRunner

private struct RenameRunner: ProcessRunner {
    let notice: String
    let failed: Bool
    var confirmation: String?

    func run(
        _ arguments: [String], workingDirectory: String?, environment: [String: String], outputLimit: Int?,
    ) async throws -> ProcessResult {
        if arguments.contains("ls-remote") {
            return ProcessResult(status: 0, standardOutput: "", standardError: confirmation ?? notice)
        }
        if arguments.contains("fetch") || arguments.contains("push") {
            return ProcessResult(status: failed ? 1 : 0, standardOutput: "", standardError: notice)
        }
        return try await FoundationProcessRunner().run(
            arguments, workingDirectory: workingDirectory, environment: environment, outputLimit: outputLimit,
        )
    }
}
