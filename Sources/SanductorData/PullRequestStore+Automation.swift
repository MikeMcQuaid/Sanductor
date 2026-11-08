import SanductorDomain

public extension PullRequestStore {
    /// Saves preferences before the dashboard can act on them.
    func updateAutomation(
        repositoryPath: String,
        summary: PullRequestSummary,
        change: (inout PullRequestAutomation) -> Void,
    ) throws {
        let key = PullRequestAutomation.key(for: summary.url)
        try store.updatePersisting { metadata in
            var state = metadata.pullRequestAutomation[key]
                ?? PullRequestAutomation(repositoryPath: repositoryPath, number: summary.number, url: summary.url)
                .applying(metadata.repositoryFeedbackDefaults[repositoryPath])
            let previous = state
            change(&state)
            if state.reviewBot != previous.reviewBot {
                var defaults = metadata.repositoryFeedbackDefaults[repositoryPath] ?? RepositoryFeedbackDefaults()
                defaults.reviewBot = state.reviewBot
                metadata.repositoryFeedbackDefaults[repositoryPath] = defaults
            }
            metadata.pullRequestAutomation[key] = state
        }
    }

    /// Records the displayed conversation locally; resolution verifies GitHub after a push.
    func toggleResolveOnPush(repositoryPath: String, summary: PullRequestSummary, thread: ReviewThread) async throws {
        let threadID = thread.resolveID
        let key = PullRequestAutomation.key(for: summary.url)
        if store.load().pullRequestAutomation[key]?.resolutions[threadID] != nil {
            try store.updatePersisting { $0.pullRequestAutomation[key]?.resolutions[threadID] = nil }
            return
        }
        try await markResolveOnPush(repositoryPath: repositoryPath, summary: summary, thread: thread)
    }

    /// Marks a thread without cancelling or replacing an existing mark from any checkout.
    func markResolveOnPush(repositoryPath: String, summary: PullRequestSummary, thread: ReviewThread) async throws {
        let threadID = thread.resolveID
        guard store.load()
            .pullRequestAutomation[PullRequestAutomation.key(for: summary.url)]?
            .resolutions[threadID] == nil
        else {
            return
        }

        let fresh = try await summaryForResolution(repositoryPath: repositoryPath, summary: summary)
        guard fresh.state == "OPEN" else {
            throw SessionServiceError("The pull request is closed. Its conversations cannot be marked Resolve on push.")
        }
        guard let head = fresh.headCommit, head.isEmpty == false,
              threadID.isEmpty == false, thread.isResolved == false, let latest = thread.comments.last?.id
        else {
            throw SessionServiceError("The pull request is still loading. Try marking this conversation again shortly.")
        }

        try updateAutomation(repositoryPath: repositoryPath, summary: fresh) { state in
            if state.resolutions[threadID] == nil {
                state.resolutions[threadID] = PendingThreadResolution(head: head, commentID: latest)
            }
        }
    }

    /// Whether this thread has a cancellable mark, including a claimed request.
    func pendingResolution(pullRequestURL: String, threadID: String) -> Bool {
        store.load().pullRequestAutomation[PullRequestAutomation.key(for: pullRequestURL)]?.resolutions[threadID] != nil
    }
}
