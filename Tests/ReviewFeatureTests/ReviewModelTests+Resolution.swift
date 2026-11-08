import Foundation
@testable import ReviewFeature
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension ReviewModelTests {
    @Test(arguments: [false, true], [false, true])
    func `reopened pull requests use the refreshed listing for resolution marks`(bulk: Bool, loaded: Bool) async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = ResolutionRunner()
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: store)
        requests.rememberSummary(repositoryPath: "/repo", summary: resolutionSummary(number: 7, state: "CLOSED"))
        let reopened = resolutionSummary(number: 7)
        requests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [reopened])
        #expect(requests.cachedSummary(repositoryPath: "/repo", number: 7)?.state == "OPEN")
        requests.rememberSummary(repositoryPath: "/repo", summary: reopened)
        let model = ReviewModel(worktreePath: "/worktree", repositoryName: "repo", git: GitClient(runner: runner))
        model.threadPullRequestNumber = loaded ? 7 : nil
        model.configureResolveOnPush(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            pullRequests: requests,
        )
        let thread = ReviewThread(id: "thread", path: "file", line: 1, isResolved: false, comments: [
            ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment"),
        ])
        let previous = ErrorLog.shared.entries.last?.id ?? 0
        if bulk {
            await model.resolveReviews?([thread], nil)
        } else {
            await model.toggleResolveOnPush(thread)
        }
        #expect(model.pendingResolution(thread))
        #expect(store.load()
            .pullRequestAutomation[PullRequestAutomation.key(for: reopened.url)]?
            .resolutions[thread.id]?
            .head == reopened.headCommit)
        #expect(ErrorLog.shared.entries.contains { $0.id > previous && $0.isError } == false)
    }

    @Test(arguments: ["OPEN", "CLOSED", "missing"])
    func `bulk conversations resolve local findings without an open PR`(state: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = ResolutionRunner()
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: store)
        let summary = resolutionSummary(number: 7, state: state)
        let thread = ReviewThread(id: "thread", path: "file", line: 1, isResolved: false, comments: [
            ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment"),
        ])
        let pending = ReviewThread(id: "pending", path: "file", line: 1, isResolved: false, comments: thread.comments)
        try await requests.markResolveOnPush(
            repositoryPath: "/other", summary: resolutionSummary(number: 7), thread: pending,
        )
        if state != "missing" {
            requests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [summary])
        }
        let outside = ReviewThread(
            id: "out", path: "file", line: 1, isResolved: false, comments: [], resolveID: "", outsideDiffReviewID: 7,
        )
        let local = ReviewThread(id: "local", path: "file", line: 1, isResolved: false, comments: [], resolveID: "")
        let uncopied = ReviewThread(
            id: "uncopied", path: "file", line: 1, isResolved: false, comments: [], resolveID: "",
        )
        let review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [local, uncopied])
        store.update { $0.localReviews["/worktree"] = review }
        let model = ReviewModel(worktreePath: "/worktree", repositoryName: "repo", git: GitClient(runner: runner))
        model.threadPullRequestNumber = 7
        model.configureResolveOnPush(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            pullRequests: requests,
        )
        let previous = ErrorLog.shared.entries.last?.id ?? 0
        await model.resolveReviews?([pending, thread, outside, local], review)
        let errors = ErrorLog.shared.entries.filter { $0.id > previous && $0.isError }
        #expect(errors.count == (state == "OPEN" ? 0 : 1))
        #expect(requests.pendingResolution(pullRequestURL: summary.url, threadID: "pending"))
        #expect(requests.pendingResolution(pullRequestURL: summary.url, threadID: "thread") == (state == "OPEN"))
        #expect(store.load().localReviews["/worktree"]?.threads.map(\.isResolved) == [true, false])
        #expect(requests.applyingOutsideDiffResolutions(to: [outside], repositoryPath: "/repo", number: 7)
            .first?
            .isResolved == true)
    }

    @Test
    func `outside diff resolution updates the mounted review without fetching threads`() async {
        var resolved = false
        let thread = ReviewThread(
            id: "out", path: "file", line: 1, isResolved: false, comments: [], resolveID: "", outsideDiffReviewID: 7,
        )
        let model = ReviewModel(
            worktreePath: "/worktree",
            repositoryName: "repo",
            git: GitClient(runner: ResolutionRunner()),
            fetchThreads: { Issue.record("Local resolution must not refresh GitHub"); return (nil, []) },
            setThreadResolved: { finding, value, number in
                #expect(finding.id == thread.id)
                #expect(number == 7)
                resolved = value
            },
        )
        model.threads = [thread]
        model.threadPullRequestNumber = 7
        await model.toggleResolved(thread)
        #expect(resolved)
        #expect(model.threads.first?.isResolved == true)
        if let current = model.threads.first {
            await model.toggleResolved(current)
        }
        #expect(resolved == false)
        #expect(model.threads.first?.isResolved == false)
    }

    @Test
    func `marking a displayed review updates local state without requesting a GitHub refresh`() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = ResolutionRunner()
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: store)
        let summary = resolutionSummary(number: 7)
        requests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [summary])
        let model = ReviewModel(worktreePath: "/worktree", repositoryName: "repo", git: GitClient(runner: runner))
        model.configureResolveOnPush(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            pullRequests: requests,
        )
        let thread = ReviewThread(id: "thread", path: "file", line: 1, isResolved: false, comments: [
            ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment"),
        ])
        store.update { metadata in
            metadata.pullRequestAutomation[PullRequestAutomation.key(for: summary.url)] = PullRequestAutomation(
                repositoryPath: "/other", number: summary.number, url: summary.url,
            )
        }
        let cacheGeneration = UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey)
        await model.toggleResolveOnPush(thread)
        #expect(model.pendingResolution(thread))
        await model.toggleResolveOnPush(thread)
        #expect(model.pendingResolution(thread) == false)
        #expect(UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey) == cacheGeneration)
    }

    private func resolutionSummary(number: Int, state: String = "OPEN") -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Work",
            url: "https://github.com/o/r/pull/7",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            headCommit: "head",
        )
    }
}

// MARK: - ResolutionRunner

private struct ResolutionRunner: ProcessRunner {
    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        Issue.record("A local resolution mark spawned \(arguments.joined(separator: " "))")
        return ProcessResult(status: 1, standardOutput: "", standardError: "Offline")
    }
}
