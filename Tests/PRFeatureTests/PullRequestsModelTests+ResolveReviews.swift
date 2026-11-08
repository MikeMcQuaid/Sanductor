import AppKit
@testable import PRFeature
@testable import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension PullRequestsModelTests {
    @Test
    func `editing a reopened PR preserves its required head refresh`() async throws {
        let model = makeModel()
        let open = resolutionSummary(head: "listed-head")
        model.pullRequests.rememberSummary(
            repositoryPath: "/repo", summary: resolutionSummary(head: "old-head", state: "CLOSED"),
        )
        model.pullRequests.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [open])
        model.selected = open
        model.performEdit = { _, _, _ in
            // Succeeds without GitHub.
        }
        model.beginEditing()
        model.prTitle = "Edited title"
        #expect(await model.saveEdits())
        let cached = try #require(model.store.load().enrichedSummaryCache[
            PullRequestStore.summaryKey(repositoryPath: "/repo", number: 1),
        ])
        #expect(cached.summary.title == "Edited title")
        #expect(cached.summary.headCommit == "listed-head")
        #expect(cached.requiresHeadRefresh)
    }

    @Test(arguments: [false, true])
    func `local resolution reports a failed metadata write`(bulk: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/state.json"
        let model = makeModel(metadataFile: file)
        let path = worktreesPath + "/feature"
        let review = LocalReview(
            reviewer: .codexCLI,
            snapshot: "s",
            revision: "r",
            threads: [resolutionThread("first"), resolutionThread("second")],
        )
        try model.store.updatePersisting { $0.localReviews[path] = review }
        try FileManager.default.removeItem(atPath: file)
        try FileManager.default.createDirectory(atPath: file, withIntermediateDirectories: false)
        let previous = ErrorLog.shared.entries.last?.id ?? 0
        if bulk {
            await model.resolveReviews(resolutionSummary(head: "head"), threads: review.threads, local: (path, review))
        } else {
            model.setLocalResolved("first", resolved: true, review: review, path: path)
        }
        #expect(model.store.load().localReviews[path]?.remaining == 2)
        #expect(ErrorLog.shared.entries.count { $0.id > previous && $0.isError } == 1)
    }

    @Test
    func `bulk resolution reports REST fallback threads once and continues marking`() async {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(threads: [
                resolutionThread("fallback", resolveID: ""), resolutionThread("another fallback", resolveID: ""),
                resolutionThread("valid"),
            ])
        }
        let previous = ErrorLog.shared.entries.last?.id ?? 0
        await model.copyUnresolvedComments(selected, resolve: true)
        let errors = ErrorLog.shared.entries.filter { $0.id > previous && $0.isError }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains("resolution IDs") == true)
        #expect(errors.first?.message.contains("Refresh") == true)
        #expect(model.pullRequests.pendingResolution(pullRequestURL: selected.url, threadID: "valid"))
        #expect(model.reviewCount(for: selected) == 2)
    }

    @Test(arguments: [false, true])
    func `legacy review copies cannot resolve a replacement with the same findings`(replaced: Bool) async throws {
        let model = makeModel()
        let path = worktreesPath + "/feature"
        var legacy = LocalReview(
            reviewer: .codexCLI,
            snapshot: "s",
            revision: "r",
            threads: [resolutionThread("first", resolveID: ""), resolutionThread("second", resolveID: "")],
        )
        legacy.runID = nil
        legacy.repositoryPath = "/repo"
        legacy.branch = "feature"
        let data = try JSONEncoder().encode(legacy)
        let review = try JSONDecoder().decode(LocalReview.self, from: data)
        let replacement = try JSONDecoder().decode(LocalReview.self, from: data)
        #expect(review.runID != nil)
        #expect(review.runID != replacement.runID)
        #expect(try JSONDecoder().decode(LocalReview.self, from: JSONEncoder().encode(review)) == review)
        model.store.update { $0.localReviews[path] = review }
        model.preparePrompt = { text in
            if replaced {
                model.store.update { $0.localReviews[path] = replacement }
            }
            return text
        }
        await model.copyUnresolvedComments(resolutionSummary(head: "head"), resolve: true)
        #expect(NSPasteboard.general.string(forType: .string) == ReviewCopy.digest(of: review.threads))
        #expect(model.store.load().localReviews[path]?.remaining == (replaced ? 2 : 0))
    }

    @Test(arguments: [false, true])
    func `review copies exclude pending threads until their mark is cancelled`(resolve: Bool) async throws {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        let pending = resolutionThread("pending")
        let open = resolutionThread("open")
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(
                threads: [pending, open],
            )
        }
        try await model.pullRequests.markResolveOnPush(
            repositoryPath: "/another-checkout", summary: selected, thread: pending,
        )
        #expect(model.reviewCount(for: selected) == 1)
        await model.copyUnresolvedComments(selected, resolve: resolve)
        #expect(NSPasteboard.general.string(forType: .string) == ReviewCopy.digest(of: [open]))
        #expect(model.reviewCount(for: selected) == (resolve ? 0 : 1))
        try await model.pullRequests.toggleResolveOnPush(repositoryPath: "/repo", summary: selected, thread: pending)
        #expect(model.reviewCount(for: selected) == (resolve ? 1 : 2))
        await model.copyUnresolvedComments(selected)
        #expect(NSPasteboard.general.string(forType: .string)
            == ReviewCopy.digest(of: resolve ? [pending] : [pending, open]))
    }

    @Test(arguments: ["/repo", "/another-checkout"])
    func `bulk review resolution preserves pending marks and resolved threads`(repositoryPath: String) async throws {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        let key = PullRequestAutomation.key(for: selected.url)
        let threads = [
            resolutionThread("open"), resolutionThread("pending"),
            resolutionThread("resolved", resolved: true), resolutionThread("fallback", resolveID: ""),
            resolutionThread("another"),
        ]
        let pending = PendingThreadResolution(
            head: "previous", commentID: "pending-comment", fixCommit: "fix", autofixAttemptID: "attempt",
        )
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(threads: threads)
            var state = PullRequestAutomation(repositoryPath: repositoryPath, number: 1, url: selected.url)
            state.resolutions["pending"] = pending
            metadata.pullRequestAutomation[key] = state
        }

        await model.copyUnresolvedComments(selected, resolve: true)
        let marked = try #require(model.store.load().pullRequestAutomation[key])
        #expect(marked.resolutions == [
            "open": PendingThreadResolution(head: "head", commentID: "open-comment"), "pending": pending,
            "another": PendingThreadResolution(head: "head", commentID: "another-comment"),
        ])
        #expect(model.store
            .load()
            .threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)]?
            .threads == threads)
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(model.store.load().pullRequestAutomation[key] == marked)
    }

    @Test(arguments: ["OPEN", "CLOSED"])
    func `bulk review resolution continues local findings after a GitHub failure`(state: String) async throws {
        let model = makeModel()
        var selected = resolutionSummary(head: state == "OPEN" ? nil : "head", state: state)
        selected.unresolvedComments = 1
        let path = worktreesPath + "/feature"
        var review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [
            resolutionThread("local", resolveID: ""), resolutionThread("resolved", resolved: true, resolveID: ""),
            resolutionThread("another", resolveID: ""),
        ])
        review.repositoryPath = "/repo"
        review.branch = "feature"
        var unrelated = review
        unrelated.branch = "other"
        model.store.update { metadata in
            metadata.localReviews[path] = review
            metadata.localReviews[path + "-other"] = unrelated
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(
                threads: [resolutionThread("remote")],
            )
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 1)] = .init(
                events: [
                    ReviewComment(
                        id: 17,
                        author: "coderabbitai[bot]",
                        body: "<details><summary>Outside diff range comments (1)</summary>\n\n"
                            + "**file.swift:42**: Validate the configuration.\n\n</details>",
                        kind: "COMMENTED",
                        authorType: "Bot",
                    ),
                ],
            )
        }
        let finding = try #require(model.pullRequests
            .cachedConversation(repositoryPath: "/repo", number: 1)
            .reviewThreads
            .first { $0.outsideDiffReviewID != nil })
        #expect(model.reviewCount(for: selected) == 4)

        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(model.reviewCount(for: selected) == 1)
        #expect(NSPasteboard.general.string(forType: .string)?.contains("Validate the configuration.") == true)
        #expect(model.store.load().resolvedOutsideDiff[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)]
            == [finding.id])
        #expect(model.store.load().localReviews[path]?.threads.allSatisfy(\.isResolved) == true)
        #expect(model.store.load().localReviews[path + "-other"] == unrelated)
        #expect(model.store.load().pullRequestAutomation.isEmpty)
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(model.reviewCount(for: selected) == 1)
    }

    @Test
    func `bulk review resolution continues marking after an invalid GitHub thread`() async {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(threads: [
                ReviewThread(id: "invalid", path: "file.swift", line: 1, isResolved: false, comments: []),
                resolutionThread("valid"),
            ])
        }
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(model.store.load().pullRequestAutomation[PullRequestAutomation.key(for: selected.url)]?.resolutions == [
            "valid": PendingThreadResolution(head: "head", commentID: "valid-comment"),
        ])
    }

    @Test
    func `bulk review resolution needs a known head for GitHub threads`() async {
        let model = makeModel()
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(
                threads: [resolutionThread("open")],
            )
        }
        await model.copyUnresolvedComments(resolutionSummary(head: nil), resolve: true)
        #expect(model.store.load().pullRequestAutomation.isEmpty)
    }

    @Test(arguments: [false, true])
    func `bulk copy captures findings before resolution and preserves replacement reviews`(replaced: Bool) async {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        let path = worktreesPath + "/feature"
        var review = LocalReview(
            reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [resolutionThread("local")],
        )
        review.repositoryPath = "/repo"
        review.branch = "feature"
        let remote = resolutionThread("remote")
        model.store.update { metadata in
            metadata.localReviews[path] = review
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(threads: [remote])
        }
        model.preparePrompt = { text in
            #expect(model.store.load().pullRequestAutomation.isEmpty)
            #expect(model.store.load().localReviews[path]?.remaining == 1)
            model.store.update { metadata in
                if replaced {
                    metadata.localReviews[path]?.runID = "replacement"
                } else {
                    metadata.localReviews[path]?.threads[0].isResolved = true
                }
            }
            return text
        }
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(NSPasteboard.general.string(forType: .string) == ReviewCopy.digest(of: [remote] + review.threads))
        #expect(model.store.load().localReviews[path]?.remaining == (replaced ? 1 : 0))
        #expect(model.store
            .load()
            .pullRequestAutomation[PullRequestAutomation.key(for: selected.url)]?
            .resolutions[remote.id] != nil)
    }

    @Test
    func `bulk copy failure leaves every finding unchanged`() async {
        let model = makeModel()
        let selected = resolutionSummary(head: "head")
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(
                threads: [resolutionThread("remote")],
            )
        }
        let previous = model.store.load()
        model.preparePrompt = { _ in throw CocoaError(.fileWriteNoPermission) }
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(model.store.load() == previous)
    }

    @Test
    func `setting a local finding resolved cannot reopen an autofixed finding`() {
        let model = makeModel()
        let path = worktreesPath + "/feature"
        let review = LocalReview(
            reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [resolutionThread("local")],
        )
        model.store.update { metadata in
            metadata.localReviews[path] = review
            metadata.localReviews[path]?.threads[0].isResolved = true
        }
        model.setLocalResolved("local", resolved: true, review: review, path: path)
        #expect(model.store.load().localReviews[path]?.remaining == 0)
    }

    @Test(arguments: ["OPEN", "CLOSED"])
    func `bulk resolution reports a shared failure once per action`(state: String) async {
        let model = makeModel()
        let selected = resolutionSummary(head: state == "OPEN" ? nil : "head", state: state)
        model.store.update { metadata in
            metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: "/repo", number: 1)] = .init(
                threads: [resolutionThread("first"), resolutionThread("second")],
            )
        }
        let previous = ErrorLog.shared.entries.last?.id ?? 0
        await model.copyUnresolvedComments(selected, resolve: true)
        let errors = ErrorLog.shared.entries.filter { $0.id > previous && $0.isError }
        #expect(errors.count == 1)
        #expect(errors.first?.message.contains(state == "OPEN" ? "loading" : "closed") == true)
        await model.copyUnresolvedComments(selected, resolve: true)
        #expect(ErrorLog.shared.entries.count { $0.id > previous && $0.isError } == 2)
    }

    private func resolutionSummary(head: String?, state: String = "OPEN") -> PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Review",
            url: "https://example.invalid/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            headCommit: head,
        )
    }

    private func resolutionThread(
        _ identifier: String, resolved: Bool = false, resolveID: String? = nil,
    ) -> ReviewThread {
        ReviewThread(
            id: identifier,
            path: "file.swift",
            line: 1,
            isResolved: resolved,
            comments: [ReviewThreadComment(author: "reviewer", body: "Finding", id: identifier + "-comment")],
            resolveID: resolveID,
        )
    }
}
