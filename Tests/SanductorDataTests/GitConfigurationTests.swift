import Foundation
@testable import SanductorData
import Testing

struct GitConfigurationTests {
    @Test
    func `host commits silently skip named and file hooks`() async throws {
        let path = try TestSupport.temporaryDirectory("skip-hooks")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let hooks = path + "/.git/hooks"
        try FileManager.default.createSymbolicLink(atPath: hooks + "/pre-commit", withDestinationPath: "/usr/bin/false")
        try await TestSupport.runGit(["config", "core.hooksPath", hooks], in: path)
        try await TestSupport.runGit(["config", "maintenance.auto", "true"], in: path)
        try await TestSupport.runGit(["config", "hook.local-check.command", "/usr/bin/false"], in: path)
        try await TestSupport.runGit(["config", "hook.local-check.event", "pre-commit"], in: path)
        try await TestSupport.runGit(["config", "hook.pre-commit.enabled", "true"], in: path)
        let runner = FoundationProcessRunner()
        let maintenance = try await runner.run(
            ["git", "config", "--get", "maintenance.auto"], workingDirectory: path, environment: [:],
        )
        #expect(maintenance.standardOutput == "false\n")
        let commit = try await runner.run(
            ["git", "commit", "--allow-empty", "-m", "Skip hooks"], workingDirectory: path, environment: [:],
        )
        #expect(commit.succeeded)
        #expect(commit.standardError.isEmpty)
        // Stand in for gh spawning Git, using only local tools and no GitHub credentials.
        try FileManager.default.createSymbolicLink(atPath: path + "/gh", withDestinationPath: "/usr/bin/env")
        let delegated = try await runner.run(
            [path + "/gh", "git", "commit", "--allow-empty", "-m", "Delegated commit"],
            workingDirectory: path,
            environment: ["PATH": "/usr/bin:/bin"],
        )
        #expect(delegated.succeeded)
        #expect(delegated.standardError.isEmpty)
        #expect(try await TestSupport.runGit(["config", "--local", "hook.local-check.command"], in: path)
            .standardOutput == "/usr/bin/false\n")
    }

    @Test
    func `remote URLs accept built-in transports and refuse external helpers without exposing credentials`() throws {
        func config(_ setting: String) -> ProcessResult {
            ProcessResult(status: 0, standardOutput: "local\0file:.git/config\0" + setting + "\0", standardError: "")
        }
        for url in ["https://example.invalid/repo", "git@example.invalid:repo", "../repo"] {
            try GitClient.checkConfiguration(config("remote.origin.url\n" + url), in: "/repo")
        }
        let failure = #expect(throws: GitClient.ConfigurationError.self) {
            try GitClient.checkConfiguration(
                config("url.fixture://private@example.invalid/.insteadof\nrepo:"), in: "/repo",
            )
        }
        #expect(failure?.localizedDescription.contains("private") == false)
        #expect(throws: GitClient.ConfigurationError.self) {
            try GitClient.checkConfiguration(config("remote.origin.pushurl\nfixture::repo"), in: "/repo")
        }
    }

    @Test(arguments: ["false", "true", "OFF", "Yes", "0", "1", ""])
    func `boolean filesystem monitors allow status and origin discovery`(value: String) async throws {
        let path = try TestSupport.temporaryDirectory("monitor")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["remote", "add", "origin", "https://github.com/Homebrew/brew.git"], in: path)
        try await TestSupport.runGit(["config", "core.fsmonitor", value], in: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let result = try await git.git(["config", "--get", "core.fsmonitor"], in: path)
        #expect(result.standardOutput == "false\n")
        #expect(await git.localState(worktreePath: path).configurationError == nil)
        #expect(await GitHubClient(runner: FoundationProcessRunner()).fullName(repositoryPath: path) == "Homebrew/brew")
    }

    @Test
    func `a refused origin lookup reports its cause and recovers after fixing an included file`() async throws {
        let path = try TestSupport.temporaryDirectory("blocked-origin")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let included = path + "/.git/monitor-config"
        try "[core]\nfsmonitor = /dev/null\n".write(toFile: included, atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["config", "include.path", included], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", "https://github.com/Homebrew/brew.git"], in: path)
        let client = GitHubClient(runner: FoundationProcessRunner()) { false }
        #expect(await client.fullName(repositoryPath: path) == nil)
        let failure = await #expect(throws: GitClient.ConfigurationError.self) {
            try await client.branchPullRequests(repositoryPath: path, branch: "topic", etag: nil)
        }
        #expect(failure?.localizedDescription.contains("core.fsmonitor") == true)
        #expect(failure?.localizedDescription.contains(included) == true)
        try "".write(toFile: included, atomically: true, encoding: .utf8)
        #expect(await client.fullName(repositoryPath: path) == "Homebrew/brew")
    }

    @Test
    func `a read in a subdirectory identifies the owning checkout config`() async throws {
        let path = try TestSupport.temporaryDirectory("config-origin")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let nested = path + "/Sources/Feature"
        try await TestSupport.makeRepository(at: path)
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try await TestSupport.runGit(["config", "filter.preview.clean", "/dev/null"], in: path)
        let blocked = await GitClient(runner: FoundationProcessRunner()).localState(worktreePath: nested)
        #expect(blocked.configurationError?.contains(path + "/.git/config") == true)
    }

    @Test(arguments: ["filter.preview.clean", "core.fsmonitor", "gpg.ssh.program", "core.sshCommand"])
    func `local program settings refuse reads and commits before staging`(key: String) async throws {
        let path = try TestSupport.temporaryDirectory("git-config")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["config", key, "/dev/null"], in: path)
        try "changed".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        let git = GitClient(runner: FoundationProcessRunner())
        let read = await #expect(throws: (any Error).self) {
            try await git.git(["rev-parse", "HEAD"], in: path, allowFailure: true)
        }
        #expect(read?.localizedDescription.lowercased().contains(key.lowercased()) == true)
        let commit = await #expect(throws: (any Error).self) {
            try await git.commitAll(worktreePath: path, message: "Refused")
        }
        #expect(commit?.localizedDescription.contains("~/.gitconfig") == true)
        #expect(try await TestSupport.runGit(["diff", "--cached", "--name-only"], in: path).standardOutput.isEmpty)
        #expect(try await TestSupport.runGit(["rev-list", "--count", "HEAD"], in: path).standardOutput == "1\n")
    }

    @Test
    func `a trusted global SSH signing program can sign a commit`() async throws {
        let root = try TestSupport.temporaryDirectory("global-signer")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["config", "core.fsmonitor", "false"], in: path)
        let key = root + "/key"
        try await TestSupport.run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key])
        let signer = root + "/trusted signer"
        try FileManager.default.createSymbolicLink(atPath: signer, withDestinationPath: "/usr/bin/ssh-keygen")
        let config = root + "/gitconfig"
        for (name, value) in [("gpg.format", "ssh"), ("gpg.ssh.program", signer), ("user.signingkey", key)] {
            try await TestSupport.runGit(["config", "--file", config, name, value], in: path)
        }
        let git = GitClient(runner: FoundationProcessRunner())
        // Isolate the signing configuration from the test runner’s own OpenSSH override.
        let environment = ["GIT_CONFIG_GLOBAL": config, "GIT_CONFIG_COUNT": "0"]
        let effective = try await git.git(["config", "--get", "gpg.ssh.program"], in: path, environment: environment)
        #expect(effective.standardOutput == signer + "\n")
        try await git.git(["commit", "--allow-empty", "-S", "-m", "Signed"], in: path, environment: environment)
        let commit = try await git.git(["cat-file", "-p", "HEAD"], in: path, environment: environment)
        #expect(commit.standardOutput.contains("gpgsig -----BEGIN SSH SIGNATURE-----"))
    }

    @Test
    func `included worktree settings block status and delegated Git`() async throws {
        let root = try TestSupport.temporaryDirectory("git-scope")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/main"
        let linked = root + "/linked"
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["worktree", "add", "-b", "topic", linked, "main"], in: path)
        try await TestSupport.runGit(["config", "extensions.worktreeConfig", "true"], in: path)
        let config = root + "/settings"
        try "[filter \"preview\"]\nclean = /dev/null\n".write(toFile: config, atomically: true, encoding: .utf8)
        let git = GitClient(runner: FoundationProcessRunner())
        let reading = try await git.git(["rev-parse", "HEAD"], in: linked, environment: ["GIT_CONFIG_GLOBAL": config])
        #expect(reading.succeeded)
        try await TestSupport.runGit(["config", "--worktree", "include.path", config], in: linked)
        let blocked = await git.localState(worktreePath: linked).configurationError
        #expect(blocked?.contains("filter.preview.clean") == true)
        #expect(blocked?.contains(config) == true)
        #expect(await git.localState(worktreePath: path).configurationError == nil)
        await #expect(throws: GitClient.ConfigurationError.self) {
            try await FoundationProcessRunner().run(["gh", "--version"], workingDirectory: linked, environment: [:])
        }
        try await TestSupport.runGit(["config", "--worktree", "--unset", "include.path"], in: linked)
        #expect(await git.localState(worktreePath: linked).configurationError == nil)
    }
}
