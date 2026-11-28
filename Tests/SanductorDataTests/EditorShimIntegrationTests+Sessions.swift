import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

/// `sanductor new` from an issue, a pull request or a discussion:
/// the command asks the app through the spool and takes its answer,
/// since only the app may ask GitHub or check a pull request out.
extension EditorShimIntegrationTests {
    @Test(arguments: [
        ("--issue 12", ExternalEdit.Source.issue, "12"),
        ("--pull-request 34", .pullRequest, "34"),
        ("--discussion https://github.com/orgs/owner/discussions/5", .discussion,
         "https://github.com/orgs/owner/discussions/5"),
    ])
    func `a source is asked of the app, which the command waits for`(
        option: String, source: ExternalEdit.Source, reference: String,
    ) async throws {
        let root = try TestSupport.temporaryDirectory("shim-session")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let edits = paths(root: root).editsDirectory
        let spool = ExternalEditSpool(directory: edits)
        // What the shell must never act on reaches the app as typed.
        let context = "Keep \"it\" `small`\n$(touch " + root + "/ran) and 'quoted'"

        let process = try start(
            "--repository repo --agent codex --model gpt-5 --effort high " + option + " --no-attach",
            root: root,
            context: context,
        )
        let request = try #require(await firstEdit(in: spool))
        #expect(request.kind == .session)
        #expect(request.waitsForAnswer)
        #expect(request.path == root + "/shared/repositories/repo")
        let session = try #require(request.session)
        #expect(session.agent == AgentKind.codexCLI.rawValue)
        #expect(session.model == "gpt-5")
        #expect(session.effort == "high")
        #expect(session.source == source)
        #expect(session.reference == reference)
        #expect(session.context == context)
        spool.claim(request)
        #expect(
            try String(contentsOfFile: edits + "/" + request.id + ".open", encoding: .utf8)
                == String(ProcessInfo.processInfo.processIdentifier) + "\n",
        )

        // Still waiting: the app has it, the agent has not started.
        try await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        #expect(process.isRunning)

        spool.finish(request, saved: true)
        try await exit(of: process)
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOfFile: root + "/out", encoding: .utf8).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: edits).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root + "/ran") == false)
        // The app makes the worktree, never the command.
        #expect(FileManager.default.fileExists(atPath: root + "/shared/worktrees") == false)
    }

    @Test
    func `a session the app could not start fails the command with the reason`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-failed")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)

        // Nothing typed: with a source the context is optional.
        let process = try start("--repository repo --agent claude --pull-request 34 --no-attach", root: root)
        let request = try #require(await firstEdit(in: spool))
        #expect(request.session?.context.isEmpty == true)
        #expect(request.session?.model.isEmpty == true)
        spool.finish(request, saved: false, message: "No pull request #34\nin owner/repo")
        try await exit(of: process)

        #expect(process.terminationStatus == 1)
        let said = try String(contentsOfFile: root + "/err", encoding: .utf8)
        #expect(said.contains("Error: No pull request #34\nin owner/repo"))
    }

    @Test
    func `an app that quit while the session started fails the command rather than holding it`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-quit")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let edits = paths(root: root).editsDirectory
        let spool = ExternalEditSpool(directory: edits)

        let process = try start("--repository repo --agent claude --pull-request 34 --no-attach", root: root)
        let request = try #require(await firstEdit(in: spool))
        // Claimed by a process that has since gone, as the app's own
        // claim reads once it has quit.
        let gone = try Process.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        try await exit(of: gone)
        try (String(gone.processIdentifier) + "\n").write(
            toFile: edits + "/" + request.id + ".open", atomically: true, encoding: .utf8,
        )
        try await exit(of: process)

        #expect(process.terminationStatus == Self.unavailable)
        let said = try String(contentsOfFile: root + "/err", encoding: .utf8)
        #expect(said.contains("Error: Sanductor quit before the session started"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: edits).isEmpty)
    }

    @Test
    func `a dry run prints the request and asks the app for nothing`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-dry")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let process = try start(
            "--repository repo --agent claude --issue 12 --no-attach", root: root, context: "Why", isDryRun: true,
        )
        try await exit(of: process)

        #expect(process.terminationStatus == 0)
        let printed = try Data(contentsOf: URL(fileURLWithPath: root + "/out"))
        let request = try #require(ExternalEdit(id: "printed", json: printed))
        #expect(request.session?.source == .issue)
        #expect(request.session?.context == "Why")
        #expect(FileManager.default.fileExists(atPath: paths(root: root).editsDirectory) == false)
    }

    @Test
    func `the repository is named as the app lists it, through a symlinked directory`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-link")
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(
            atPath: root + "/volume/repo/.git", withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(atPath: root + "/projects", withDestinationPath: "volume")

        let process = try start(
            "--repository repo --agent claude --issue 12 --no-attach",
            root: root,
            isDryRun: true,
            publishing: "repositories-directory=" + root + "/projects\n",
        )
        try await exit(of: process)

        // The app lists checkouts under the directory Settings names,
        // which is where it will look this one up.
        let printed = try Data(contentsOf: URL(fileURLWithPath: root + "/out"))
        #expect(ExternalEdit(id: "printed", json: printed)?.path == root + "/projects/repo")
    }

    @Test
    func `an answer to a command that has gone is not left in the spool`() throws {
        let root = try TestSupport.temporaryDirectory("shim-session-gone")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let edits = paths(root: root).editsDirectory
        try FileManager.default.createDirectory(atPath: edits, withIntermediateDirectories: true)
        // Interrupted while its session started, the command took its
        // request with it; the app's answer arrives afterwards.
        let request = ExternalEdit(
            id: "gone", path: root, workingDirectory: root, processIdentifier: 0, kind: .session,
        )

        ExternalEditSpool(directory: edits).finish(request, saved: true)

        #expect(try FileManager.default.contentsOfDirectory(atPath: edits).isEmpty)
    }

    @Test
    func `the sandbox user is refused a source rather than left waiting`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-sandbox")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let process = try start(
            "--repository repo --agent claude --issue 12 --no-attach", root: root, home: "/Users/sandvault-test",
        )
        try await exit(of: process)

        #expect(process.terminationStatus == Self.unavailable)
        let said = try String(contentsOfFile: root + "/err", encoding: .utf8)
        #expect(said.contains("Error: --issue cannot be used by the sandbox user"))
        #expect(FileManager.default.fileExists(atPath: paths(root: root).editsDirectory) == false)
    }

    @Test(arguments: [
        "--issue 12 --pull-request 34", "--issue twelve", "--pull-request 034", "--issue ''",
        "--discussion https://example.com/owner/repo/discussions/5",
        "--discussion https://github.com/owner/repo/discussions/5/edit",
        "--discussion 'https://github.com/owner/repo/discussions/5?a=$(id)'",
        "--discussion https://github.com/owner/repo/issues/5",
    ])
    func `a source the command cannot make sense of is refused before the app is asked`(
        option: String,
    ) async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-refused")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let process = try start("--repository repo --agent claude " + option + " --no-attach", root: root)
        try await exit(of: process)

        #expect(process.terminationStatus == Self.usage)
        #expect(FileManager.default.fileExists(atPath: paths(root: root).editsDirectory) == false)
    }

    @Test
    func `a source needs the repository and the flag a typed prompt does`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-session-interactive")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let process = try start("--issue 12", root: root)
        try await exit(of: process)

        #expect(process.terminationStatus == Self.usage)
        #expect(try String(contentsOfFile: root + "/err", encoding: .utf8).contains("--no-attach"))
    }

    // MARK: Private

    /// sysexits' usage error and unavailable service, as the command
    /// reports a bad argument and an app it cannot reach.
    private static let usage: Int32 = 64
    private static let unavailable: Int32 = 69

    /// Runs `sanductor new` with its context on standard input, as
    /// the host user unless told otherwise: under test the home may
    /// be the sandbox user's own, which the command refuses. What it
    /// prints lands in `out` and `err` beside the workspace.
    private func start(
        _ arguments: String,
        root: String,
        context: String = "",
        home: String? = nil,
        isDryRun: Bool = false,
        publishing: String = "",
    ) throws -> Process {
        try FileManager.default.createDirectory(
            atPath: root + "/shared/repositories/repo/.git", withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(atPath: root + "/shared/sanductor", withIntermediateDirectories: true)
        try ("codex-models=gpt-5\ncodex-gpt-5-efforts=high\n" + publishing).write(
            toFile: root + "/shared/sanductor/session-defaults", atomically: true, encoding: .utf8,
        )
        let shim = shim(root: root)
        let command = "printf '%s' " + context.shellQuoted + " | HOME=" + (home ?? root + "/host").shellQuoted
            + (isDryRun ? " SANDUCTOR_DRY_RUN=1 " : " ") + shim.path.shellQuoted + " new " + arguments
            + " >" + (root + "/out").shellQuoted + " 2>" + (root + "/err").shellQuoted
        return try run(
            shim, arguments: ["-c", command], in: root, sharedWorkspace: root + "/shared", executable: "/bin/sh",
        )
    }
}
