import Foundation
@testable import ReviewFeature
@testable import SanductorData
import SanductorDomain
import Testing

extension ReviewModelTests {
    @Test
    func `outside diff resolves follow loaded threads when the branch cache changes`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await makeRepository(at: root)
        let service = outsideDiffService(root: root, numbers: [7, 8])
        let requests = service.pullRequestReads
        let worktree = Worktree(repositoryName: "repo", repositoryPath: root, branch: "main", path: root)
        let model = ReviewView.reviewModel(
            worktree: worktree, git: service.git, github: service.github, service: service,
        )
        let first = PullRequestSummary(
            number: 7, title: "First", url: "", headBranch: "main", mergeable: "", reviewDecision: "", checks: "",
        )
        let next = PullRequestSummary(
            number: 8, title: "Next", url: "", headBranch: "main", mergeable: "", reviewDecision: "", checks: "",
        )
        requests.rememberListing(repositoryPath: root, scope: .branch("main"), summaries: [first])
        await model.reload()
        let finding = try #require(model.threads.first)
        requests.rememberListing(repositoryPath: root, scope: .branch("main"), summaries: [next])
        await model.toggleResolved(finding)
        #expect(requests.cachedConversation(repositoryPath: root, number: 7).reviewThreads.first?.isResolved == true)
        #expect(requests.cachedConversation(repositoryPath: root, number: 8).reviewThreads.first?.isResolved == false)
        model.reapplyOutsideDiffResolutions(pullRequests: requests, repositoryPath: root)
        #expect(model.threads.first?.isResolved == true)
        await model.reloadThreads()
        #expect(model.threadPullRequestNumber == 8)
        #expect(model.threads.first?.isResolved == false)
        requests.rememberListing(repositoryPath: root, scope: .branch("main"), summaries: [first])
        model.reapplyOutsideDiffResolutions(pullRequests: requests, repositoryPath: root)
        #expect(model.threads.first?.isResolved == false)
    }

    private func outsideDiffService(root: String, numbers: [Int]) -> SessionService {
        let paths = WorkspacePaths(
            hostUser: "test", sharedWorkspace: root, sandboxHome: root, metadataFile: root + "/state",
        )
        let store = MetadataStore(file: paths.metadataFile)
        let event = ReviewComment(
            id: 1,
            author: "coderabbitai[bot]",
            body: "<details><summary>Outside diff comments (1)</summary>\n\n"
                + "**README.md:1**: Check this.\n\n</details>",
            kind: "COMMENTED",
            authorType: "Bot",
        )
        for number in numbers {
            let key = PullRequestStore.conversationKey(repositoryPath: root, number: number)
            store.update { metadata in
                metadata.conversationCache[key] = CachedConversation(events: [event])
                metadata.fetchedAt[key] = Date()
            }
        }
        let runner = FoundationProcessRunner()
        return SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true),
            github: GitHubClient(runner: OutsideDiffRunner()),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: store,
            runners: [],
        )
    }
}

// MARK: - OutsideDiffRunner

private struct OutsideDiffRunner: ProcessRunner {
    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        Issue.record("Unexpected GitHub request: \(arguments)")
        return ProcessResult(status: 1, standardOutput: "", standardError: "Offline")
    }
}
