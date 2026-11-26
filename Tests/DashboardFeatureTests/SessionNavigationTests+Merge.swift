@testable import DashboardFeature
import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["clean", "dirty", "moved", "held", "busy", "unpushed"])
    func `an observed merge advances a clean checkout in stack order`(scenario: String) async throws {
        let fixture = Fixture(runner: FoundationProcessRunner())
        defer { fixture.close() }
        let path = fixture.repository.path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        func git(_ arguments: [String]) async throws -> String {
            let result = try await FoundationProcessRunner().run(
                ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"]
                    + arguments,
                workingDirectory: path,
                environment: [:],
            )
            try #require(result.succeeded, "Git failed: \(result.standardError)")
            return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let branches = ["lower", "z-middle", "a-top"]
        _ = try await git(["init", "-b", "lower"])
        _ = try await git(["commit", "--allow-empty", "-m", "Merged"])
        _ = try await git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        _ = try await git(["switch", "-c", "z-middle"])
        _ = try await git(["commit", "--allow-empty", "-m", "Next"])
        _ = try await git(["branch", "a-top"])
        _ = try await git(["switch", "lower"])
        if scenario == "dirty" {
            try "edit".write(toFile: path + "/untracked", atomically: true, encoding: .utf8)
        } else if scenario == "moved" {
            _ = try await git(["switch", "a-top"])
        } else if scenario == "held" {
            _ = try await git(["worktree", "add", path + "-sibling", "z-middle"])
        }
        if scenario == "unpushed" {
            _ = try await git(["commit", "--allow-empty", "-m", "Local work"])
        }
        let model = fixture.model
        let busy = AgentSession(name: "test", agent: .codexCLI, status: .running, activity: .working)
        let item = try #require(model.groups.first?.items.first)
            .renamed(branch: "lower")
            .with(session: scenario == "busy" ? busy : nil)
        model.groups = [RepositoryGroup(repository: fixture.repository, items: [item], defaultBranch: "main")]
        model.selection = item
        model.derivedStacks[path] = BranchStack(base: "main", branches: branches, checkedOut: "lower")
        model.pullRequests.rememberBranchSummary(lowerPullRequest("OPEN"), repositoryPath: path, branch: "lower")
        model.pullRequests.rememberListing(
            repositoryPath: path, scope: .branch("lower"), summaries: [lowerPullRequest("MERGED")],
        )
        model.store.update { $0.fetchedAt["queue#" + path] = Date() }
        await model.refreshStalePullRequests(forcing: [])
        let expected = scenario == "clean" ? "z-middle" : (scenario == "moved" ? "a-top" : "lower")
        #expect(try await git(["branch", "--show-current"]) == expected)
        #expect(model.selection?.worktree.path == path)
    }

    @Test(arguments: ["idle", "requested", "queued", "expired"])
    func `the usual poll speeds up for requested and queued merges`(state: String) async {
        let fixture = Fixture(runner: MergePollRunner(queued: state == "queued"))
        defer { fixture.close() }
        let model = fixture.model
        let repository = fixture.repository
        model.groups[0] = RepositoryGroup(repository: repository, items: model.groups[0].items, defaultBranch: "other")
        model.store.update { metadata in
            metadata.pullRequestCache[repository.path + "#main"] = PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "main",
                mergeable: "MERGEABLE",
                reviewDecision: "APPROVED",
                checks: "SUCCESS",
                state: "OPEN",
            )
        }
        if state == "requested" || state == "expired" {
            model.pullRequests.markMergeRequested(repositoryPath: repository.path, branches: ["main"])
        }
        let listing = PullRequestStore.listingKey(repositoryPath: repository.path, scope: .branch("main"))
        let queue = "queue#" + repository.path
        let before = Date().addingTimeInterval(-RefreshCadence.slowed(90, onBattery: PowerSource.isOnBattery))
        model.store.update { metadata in
            metadata.fetchedAt[listing] = before
            metadata.fetchedAt[queue] = before
            metadata.queuedCache[repository.path] = state == "queued" ? [7] : []
            if state == "expired" {
                metadata.fetchedAt[PullRequestStore.mergeRequestKey(repositoryPath: repository.path, branch: "main")] =
                    Date().addingTimeInterval(-RefreshCadence.mergeRequestPatience)
            }
        }

        await model.refreshStalePullRequests(forcing: [])

        let faster = state == "requested" || state == "queued"
        #expect((model.store.load().fetchedAt[listing] != before) == faster)
        #expect((model.store.load().fetchedAt[queue] != before) == faster)
    }

    private func lowerPullRequest(_ state: String) -> PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Lower",
            url: "",
            headBranch: "lower",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            closedAt: state == "MERGED" ? Date() : nil,
        )
    }
}

// MARK: - MergePollRunner

private struct MergePollRunner: ProcessRunner {
    let queued: Bool

    @concurrent
    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) async -> ProcessResult {
        let output: String
        if arguments.first == "git" {
            output = "git@github.com:owner/repo.git"
        } else if arguments.contains("graphql") {
            let nodes = queued ? #"{"pullRequest":{"number":7}}"# : ""
            output = #"{"data":{"r0":{"mergeQueue":{"entries":{"nodes":[\#(nodes)]}}}}}"#
        } else {
            output = "HTTP/2.0 200 OK\r\n\r\n[]"
        }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}
