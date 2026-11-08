import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension ResolveOnPushTests {
    @Test
    func `an empty reopened summary cannot be remembered as a fresh head`() async throws {
        let root = try TestSupport.temporaryDirectory("empty-reopened-head")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(
            github: GitHubClient(runner: ResolutionRefreshRunner(fails: false, empty: true)) { true }, store: store,
        )
        requests.rememberSummary(repositoryPath: "/repo", summary: reopeningSummary(number: 7, state: "CLOSED"))
        requests.rememberListing(
            repositoryPath: "/repo", scope: .branch("feature"), summaries: [reopeningSummary(number: 7, state: "OPEN")],
        )
        requests.markChecksPending(repositoryPath: "/repo", branches: ["feature"])
        #expect(try await requests.summary(repositoryPath: "/repo", number: 7) == nil)
        let cached = try #require(store.load().enrichedSummaryCache[
            PullRequestStore.summaryKey(repositoryPath: "/repo", number: 7),
        ])
        #expect(cached.requiresHeadRefresh)
        #expect(try JSONDecoder().decode(CachedSummary.self, from: JSONEncoder().encode(cached)).requiresHeadRefresh)
    }

    @Test(arguments: [false, true], ["listed", "listed-offline", "unlisted", "offline", "empty", "closed"])
    func `reopened marks refresh the head once before accepting threads`(bulk: Bool, state: String) async throws {
        let root = try TestSupport.temporaryDirectory("reopened-marks")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")
        let fails = ["listed-offline", "offline", "empty", "closed"].contains(state)
        let runner = ResolutionRefreshRunner(
            fails: state.contains("offline"), empty: state == "empty", state: state == "closed" ? "CLOSED" : "OPEN",
        )
        let requests = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: store)
        requests.rememberSummary(repositoryPath: "/repo", summary: reopeningSummary(number: 7, state: "CLOSED"))
        let listed = reopeningSummary(number: 7, state: "OPEN")
        if state.hasPrefix("listed") {
            requests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [listed])
        } else {
            store.update { metadata in
                metadata.fetchedAt[PullRequestStore.summaryKey(repositoryPath: "/repo", number: 7)] = Date()
            }
        }
        let threads = ["first", "second"].map { id in
            ReviewThread(id: id, path: "file", line: 1, isResolved: false, comments: [
                ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment"),
            ])
        }
        let local = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [
            ReviewThread(id: "local", path: "file", line: 1, isResolved: false, comments: [], resolveID: ""),
        ])
        store.update { $0.localReviews["/worktree"] = local }
        if bulk {
            let errors = await requests.resolveReviews(
                threads + local.threads,
                repositoryPath: "/repo",
                number: 7,
                summary: listed,
                local: ("/worktree", local),
            )
            #expect(errors.isEmpty == (fails == false))
            #expect(errors.count <= 1)
        } else {
            do {
                try await requests.markResolveOnPush(repositoryPath: "/repo", summary: listed, thread: threads[0])
                #expect(fails == false)
            } catch {
                #expect(fails)
            }
        }
        #expect(runner.calls.withLock { $0 } == 1)
        let marks = store.load().pullRequestAutomation[PullRequestAutomation.key(for: listed.url)]?.resolutions ?? [:]
        #expect(marks.count == (fails ? 0 : (bulk ? 2 : 1)))
        #expect(marks.values.allSatisfy { $0.head == "fresh-head" })
        #expect(store.load().localReviews["/worktree"]?.remaining == (bulk ? 0 : 1))
    }

    private func reopeningSummary(number: Int, state: String) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Work",
            url: "https://github.com/o/r/pull/7",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            headCommit: "listed-head",
            checkDetails: [],
        )
    }
}

// MARK: - ResolutionRefreshRunner

private final class ResolutionRefreshRunner: ProcessRunner, Sendable {
    // MARK: Lifecycle

    init(fails: Bool, empty: Bool = false, state: String = "OPEN") {
        self.fails = fails
        self.empty = empty
        self.state = state
    }

    deinit {
        // No resources to release.
    }

    // MARK: Internal

    let calls: Mutex = .init(0)
    let fails: Bool
    let empty: Bool
    let state: String

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        guard arguments.contains("view") else {
            return ProcessResult(status: 0, standardOutput: "git@github.com:o/r.git\n", standardError: "")
        }

        calls.withLock { $0 += 1 }
        return ProcessResult(
            status: fails ? 1 : 0,
            standardOutput: empty ? "null" : #"""
            {"number":7,"title":"Work","url":"https://github.com/o/r/pull/7","headRefName":"feature",
             "headRefOid":"fresh-head","state":"\#(state)","statusCheckRollup":[]}
            """#,
            standardError: fails ? "Offline" : "",
        )
    }
}
