import SanductorDomain

public extension PullRequestStore {
    /// Resolves copied findings and returns each distinct failure once.
    func resolveReviews(
        _ threads: [ReviewThread],
        repositoryPath: String,
        number: Int?,
        summary: PullRequestSummary?,
        local: (path: String, review: LocalReview)?,
    ) async -> [String] {
        let localIDs = Set(local?.review.threads.map(\.id) ?? [])
        var failures = [String]()
        var markingSummary = summary
        if let summary, threads.contains(where: { thread in
            thread.isResolved == false && localIDs.contains(thread.id) == false && thread.resolveID.isEmpty == false
                && pendingResolution(pullRequestURL: summary.url, threadID: thread.resolveID) == false
        }) {
            do {
                markingSummary = try await summaryForResolution(repositoryPath: repositoryPath, summary: summary)
            } catch {
                failures.append(error.localizedDescription)
                markingSummary = nil
            }
        }
        for thread in threads where thread.isResolved == false {
            do {
                if let local, localIDs.contains(thread.id) {
                    try setLocalResolved(thread.id, resolved: true, review: local.review, path: local.path)
                } else if thread.outsideDiffReviewID != nil {
                    try setOutsideDiffResolved(thread, resolved: true, repositoryPath: repositoryPath, number: number)
                } else if thread.resolveID.isEmpty {
                    throw SessionServiceError(
                        "GitHub did not supply resolution IDs for some conversations. Refresh conversations and retry.",
                    )
                } else if let markingSummary {
                    try await markResolveOnPush(repositoryPath: repositoryPath, summary: markingSummary, thread: thread)
                } else if summary == nil {
                    throw SessionServiceError(
                        "The pull request is still loading. Try marking this conversation again shortly.",
                    )
                }
            } catch {
                let message = error.localizedDescription
                if failures.contains(message) == false {
                    failures.append(message)
                }
            }
        }
        return failures
    }

    /// Changes only the captured review's finding, preserving concurrent updates.
    func setLocalResolved(_ threadID: String, resolved: Bool, review: LocalReview, path: String) throws {
        try store.updatePersisting { metadata in
            guard let runID = review.runID, var current = metadata.localReviews[path], current.runID == runID,
                  let index = current.threads.firstIndex(where: { $0.id == threadID })
            else {
                return
            }

            current.threads[index].isResolved = resolved
            metadata.localReviews[path] = current
        }
    }
}
