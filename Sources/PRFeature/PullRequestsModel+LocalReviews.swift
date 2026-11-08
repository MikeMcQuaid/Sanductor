import SanductorData
import SanductorDomain
import TerminalUI

extension PullRequestsModel {
    func resolveReviews(
        _ summary: PullRequestSummary, threads: [ReviewThread], local: (path: String, review: LocalReview)?,
    ) async {
        for failure in await pullRequests.resolveReviews(
            threads, repositoryPath: repository.path, number: summary.number, summary: summary, local: local,
        ) {
            report(failure)
        }
        UtilityTabTarget.resolutionMarksChanged()
        if local != nil {
            UtilityTabTarget.pullRequestCacheChanged()
        }
    }

    func localReview(for summary: PullRequestSummary) -> (path: String, review: LocalReview)? {
        let metadata = store.load()
        let state = metadata.pullRequestAutomation[PullRequestAutomation.key(for: summary.url)]
        let paths = metadata.localReviews.keys.sorted { left, right in
            if left == right {
                return false
            }
            if left == worktreePath {
                return true
            }
            if right == worktreePath {
                return false
            }
            return left < right
        }
        for path in paths {
            guard let review = metadata.localReviews[path], review.failure == nil else {
                continue
            }

            let recorded = review.repositoryPath == repository.path && review.branch == summary.headBranch
                && (review.pullRequestURL == nil || review.pullRequestURL == summary.url)
                && (summary.headRepository == nil || review.headRepository == summary.headRepository)
            let collected = state?.repositoryPath == repository.path && state?.number == summary.number
                && state?.feedbackWorktreePath == path && review.runID != nil
                && state?.collection?.review?.runID == review.runID
            if recorded || collected {
                return (path, review)
            }
        }
        return nil
    }

    func reviewCount(for summary: PullRequestSummary) -> Int {
        _ = botAsks
        return copyableRemoteReviews(for: summary).count + (localReview(for: summary)?.review.remaining ?? 0)
    }

    func copyableRemoteReviews(for summary: PullRequestSummary) -> [ReviewThread] {
        ReviewCopy.copyable(
            pullRequests.cachedConversation(repositoryPath: repository.path, number: summary.number).reviewThreads,
        ) { pullRequests.pendingResolution(pullRequestURL: summary.url, threadID: $0.resolveID) }
    }

    func restoreLocalReview(for summary: PullRequestSummary) async {
        guard localReview(for: summary) == nil else {
            return
        }

        let candidates = items.filter { item in
            item.worktree.repositoryPath == repository.path && item.worktree.branch == summary.headBranch
        }
        for item in candidates where await restoreLocalReviewIdentity(item.worktree.path, summary) {
            UtilityTabTarget.pullRequestCacheChanged()
        }
    }

    func setLocalResolved(_ threadID: String, resolved: Bool, review: LocalReview, path: String) {
        do {
            try pullRequests.setLocalResolved(threadID, resolved: resolved, review: review, path: path)
            UtilityTabTarget.pullRequestCacheChanged()
        } catch {
            report(error.localizedDescription)
        }
    }
}
