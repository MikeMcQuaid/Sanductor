import AppKit
import Observation
@testable import PRFeature
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [
        "<details><summary>⚠️ Outside diff range comments (1)</summary>\n\n"
            + "**src/config.py:42-45**: Validate the configuration.\n\n</details>",
        "> [!CAUTION]\n>\n> **⚠️ Outside diff range comments (1)**\n>\n"
            + "> <details><summary>Major</summary>\n>\n> `src/config.py:42-45`\n"
            + "> Validate the configuration.\n>\n> </details>",
    ])
    func `reviews copy includes outside diff findings without unresolved GitHub threads`(body: String) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let model = makeModel()
        let selected = summary(7, head: "feature")
        model.store.update { metadata in
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)] = .init(
                events: [
                    ReviewComment(
                        id: 17, author: "coderabbitai[bot]", body: body, kind: "COMMENTED", authorType: "Bot",
                    ),
                ],
            )
        }
        #expect(model.reviewCount(for: selected) == 1)
        #expect(model.withCachedUnresolved(selected).unresolvedComments == 0)
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        let copied = pasteboard.string(forType: .string)
        #expect(copied?.contains("src/config.py\n:42 coderabbitai[bot]:") == true)
        #expect(copied?.contains("Validate the configuration.") == true)
        let finding = try #require(model.pullRequests
            .cachedConversation(
                repositoryPath: "/repo", number: 7,
            )
            .reviewThreads
            .first)
        try model.pullRequests.setOutsideDiffResolved(finding, resolved: true, repositoryPath: "/repo", number: 7)
        #expect(model.reviewCount(for: selected) == 0)
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string)?.isEmpty == true)
        try model.pullRequests.setOutsideDiffResolved(finding, resolved: false, repositoryPath: "/repo", number: 7)
        let changed = Mutex(false)
        withObservationTracking {
            #expect(model.reviewCount(for: selected) == 1)
        } onChange: {
            changed.withLock { $0 = true }
        }
        model.store.update { metadata in
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)] = .init(
                events: [
                    ReviewComment(id: 18, author: "coderabbitai[bot]", body: "", kind: "COMMENTED", authorType: "Bot"),
                ],
            )
        }
        model.botAsks += 1
        #expect(changed.withLock { $0 })
        #expect(model.reviewCount(for: selected) == 0)
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string)?.isEmpty == true)
    }

    @Test
    func `conversation copies include local findings without enabling autofix`() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let path = worktreesPath + "/feature"
        let model = makeModel(items: [item(branch: "feature", ahead: 0)], worktreePath: path)
        let selected = summary(7, head: "feature")
        let local = ReviewThread(
            id: "R1",
            path: "file.swift",
            line: 4,
            isResolved: false,
            comments: [ReviewThreadComment(author: "Codex", body: "Local finding")],
            resolveID: "",
        )
        let review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [local])
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 7, url: selected.url)
        state.feedbackWorktreePath = path
        var collection = LocalFeedbackCollection(id: "collection", revision: "r", configuration: "codex")
        collection.review = review
        collection.isPending = false
        state.collection = collection
        model.store.update { value in
            value.localReviews[path] = review
            value.pullRequestAutomation[PullRequestAutomation.key(for: selected.url)] = state
        }
        let remote = ReviewThread(
            id: "github",
            path: "file.swift",
            line: 8,
            isResolved: false,
            comments: [ReviewThreadComment(author: "copilot", body: "Remote finding")],
        )
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 7)] = .init(threads: [remote])
        }
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string) == ReviewThread.digest(of: [remote, local]))
    }

    @Test
    func `local findings stay with their captured branch repository and fork`() {
        let model = makeModel(items: [item(branch: "other", ahead: 0)])
        var review = localReview()
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: summary(7, head: "feature"))?.review == review)
        #expect(model.localReview(for: summary(8, head: "other")) == nil)
        review.repositoryPath = "/different-repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: summary(7, head: "feature")) == nil)
        review.repositoryPath = "/repo"
        review.pullRequestURL = "https://github.com/owner/repo/pull/7"
        review.headRepository = "fork/repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        let fork = PullRequestSummary(
            number: 7,
            title: "",
            url: review.pullRequestURL ?? "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headRepository: "fork/repo",
        )
        #expect(model.localReview(for: fork)?.review == review)
        #expect(model.localReview(for: summary(7, head: "feature")) == nil)
        review.headRepository = "another-fork/repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: fork) == nil)
    }

    @Test
    func `local resolution changes copy counts and cannot change a replacement review`() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let model = makeModel()
        let review = localReview()
        let path = "/worktrees/feature"
        model.store.update { $0.localReviews[path] = review }
        let selected = summary(7, head: "feature")
        #expect(model.reviewCount(for: selected) == 1)
        model.setLocalResolved("R1", resolved: true, review: review, path: path)
        #expect(model.reviewCount(for: selected) == 0)
        #expect(model.localReview(for: selected)?.review.threads.first?.codeContext == "captured code")
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string)?.isEmpty == true)
        model.setLocalResolved("R1", resolved: false, review: review, path: path)
        #expect(model.reviewCount(for: selected) == 1)
        await model.copyUnresolvedComments(selected, pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string) == ReviewThread.digest(of: review.threads))
        let replacement = localReview()
        model.store.update { $0.localReviews[path] = replacement }
        model.setLocalResolved("R1", resolved: true, review: review, path: path)
        #expect(model.localReview(for: selected)?.review == replacement)
    }

    @Test
    func `copies use local decisions without restoring reviews or fetching GitHub`() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let model = makeModel()
        model.stacking.stack = BranchStack(base: "main", branches: ["feature", "upper"], checkedOut: "upper")
        let review = localReview()
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        model.restoreLocalReviewIdentity = { _, _ in
            Issue.record("Copy must not restore reviews")
            return false
        }
        await model.copyUnresolvedComments(summary(7, head: "feature"), pasteboard: pasteboard)
        let expected = "Feedback for feature (stack: main → feature → upper)\n\n"
            + ReviewThread.digest(of: review.threads)
        #expect(pasteboard.string(forType: .string) == expected)
    }

    @Test
    func `review threads open in the worktree holding the head branch`() {
        let elsewhere = item(branch: "feature", ahead: 0, path: "/elsewhere/feature")
        let shown = item(branch: "feature", ahead: 0)
        let model = makeModel(
            items: [elsewhere, shown, item(branch: "other", ahead: 0)], worktreePath: shown.worktree.path,
        )
        let alone = makeModel(items: [elsewhere])
        let host = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: "/repo",
                branch: "feature",
                path: "/mine",
                isHostDirectory: true,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        let hostOnly = makeModel(items: [host])
        for seeded in [model, alone, hostOnly] {
            seeded.store.update { metadata in
                metadata.pullRequestCache[PullRequestStore.branchKey(repositoryPath: "/repo", branch: "feature")] =
                    summary(7, head: "feature")
            }
        }
        #expect(model.checkoutPath(for: summary(7, head: "feature")) == shown.worktree.path)
        #expect(alone.checkoutPath(for: summary(7, head: "feature")) == "/elsewhere/feature")
        #expect(model.checkoutPath(for: summary(8, head: "unchecked")) == "/repo")
        // Another fork's pull request from a same-named branch.
        #expect(model.checkoutPath(for: summary(9, head: "feature")) == "/repo")
        // A directory of your own only borrows the repository's path.
        #expect(hostOnly.checkoutPath(for: summary(7, head: "feature")) == "/repo")
    }

    private func localReview() -> LocalReview {
        var review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [
            ReviewThread(
                id: "R1",
                path: "file.swift",
                line: 1,
                isResolved: false,
                comments: [ReviewThreadComment(author: "Codex", body: "Local finding")],
                resolveID: "",
                codeContext: "captured code",
            ),
        ])
        review.repositoryPath = "/repo"
        review.branch = "feature"
        return review
    }
}
