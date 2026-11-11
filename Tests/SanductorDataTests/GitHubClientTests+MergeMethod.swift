@testable import SanductorData
import Synchronization
import Testing

extension GitHubClientTests {
    @Test(arguments: [
        // A merge commit wins whenever everything allows it.
        ([true, true, true], "", "--merge"),
        ([false, true, true], "", "--rebase"),
        ([false, false, true], "", "--squash"),
        // A ruleset on the base narrows what the settings allow.
        ([true, false, true], "squash\n", "--squash"),
        ([true, true, true], "rebase,squash\nsquash,merge\n", "--squash"),
        // Rules that cannot be read leave the settings to decide.
        ([true, true, true], nil, "--merge"),
    ])
    func `merge methods follow the settings and the base branch's rulesets`(
        allowed: [Bool], rules: String?, flag: String,
    ) async throws {
        let runner = MergeMethodRunner(allowed: allowed, rules: rules)
        try await GitHubClient(runner: runner) { true }.enableAutomerge(repositoryPath: "/repo", number: 7)
        #expect(runner.merges.withLock { $0 } == [["gh", "pr", "merge", "7", "--auto", flag]])
    }

    @Test
    func `the rules read escapes the base branch and reads every page`() async throws {
        let runner = MergeMethodRunner(allowed: [true, true, true], rules: "squash\n", base: "release#1/a%b")
        try await GitHubClient(runner: runner) { true }.enableAutomerge(repositoryPath: "/repo", number: 7)
        let read = try #require(runner.rulesReads.withLock { $0 }.first)
        #expect(read.contains("repos/{owner}/{repo}/rules/branches/release%231/a%25b?per_page=100"))
        #expect(read.contains("--paginate"))
        #expect(runner.merges.withLock { $0 } == [["gh", "pr", "merge", "7", "--auto", "--squash"]])
    }

    @Test
    func `unreadable merge settings default to a merge commit`() async throws {
        let runner = RecordingRunner()
        try await GitHubClient(runner: runner) { true }.enableAutomerge(repositoryPath: "/repo", number: 7)
        #expect(runner.commands.contains { $0.contains { $0.contains("rules/branches") } } == false)
        #expect(runner.commands.last == ["gh", "pr", "merge", "7", "--auto", "--merge"])
    }
}

// MARK: - MergeMethodRunner

private final class MergeMethodRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    /// Nil rules fail their read.
    init(allowed: [Bool], rules: String?, base: String = "main") {
        self.allowed = allowed
        self.rules = rules
        self.base = base
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    let merges: Mutex = .init([[String]]())
    let rulesReads: Mutex = .init([[String]]())

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        if arguments.contains(where: { $0.hasPrefix("repos/{owner}/{repo}/rules/branches/") }) {
            rulesReads.withLock { $0.append(arguments) }
            return ProcessResult(status: rules == nil ? 1 : 0, standardOutput: rules ?? "", standardError: "")
        }
        if arguments.contains(where: { $0.contains("mergeCommitAllowed") }) {
            let fields = zip(["mergeCommitAllowed", "rebaseMergeAllowed", "squashMergeAllowed"], allowed)
                .map { #""\#($0)":\#($1)"# }
            let settings = "{" + fields.joined(separator: ",") + #","pullRequest":{"baseRefName":"\#(base)"}}"#
            return ProcessResult(status: 0, standardOutput: settings, standardError: "")
        }
        merges.withLock { $0.append(arguments) }
        return ProcessResult(status: 0, standardOutput: "", standardError: "")
    }

    // MARK: Private

    private let allowed: [Bool]
    private let rules: String?
    private let base: String
}
