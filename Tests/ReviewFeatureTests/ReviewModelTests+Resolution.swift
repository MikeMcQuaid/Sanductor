import Foundation
@testable import ReviewFeature
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension ReviewModelTests {
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
    func `marking a displayed review updates local state without requesting a GitHub refresh`() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let runner = ResolutionRunner()
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: store)
        let summary = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://github.com/o/r/pull/7",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "head",
        )
        requests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [summary])
        let model = ReviewModel(worktreePath: "/worktree", repositoryName: "repo", git: GitClient(runner: runner))
        model.configureResolveOnPush(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            pullRequests: requests,
        )
        let thread = ReviewThread(id: "thread", path: "file", line: 1, isResolved: false, comments: [
            ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment"),
        ])
        let cacheGeneration = UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey)
        model.toggleResolveOnPush(thread)
        #expect(model.pendingResolution(thread))
        model.toggleResolveOnPush(thread)
        #expect(model.pendingResolution(thread) == false)
        #expect(UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey) == cacheGeneration)
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
