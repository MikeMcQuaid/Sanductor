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

        for worktree in worktrees(holding: summary) where await restoreLocalReviewIdentity(worktree.path, summary) {
            UtilityTabTarget.pullRequestCacheChanged()
        }
    }

    /// Where a pull request's review threads open: the worktree that
    /// has its head branch checked out, the one on screen first, so a
    /// thread's lines meet the code they were left on, or the
    /// repository's own checkout when no worktree holds it. A holder
    /// must be the branch the sidebar found this pull request for: its
    /// listing (`GitHubClient.branchPullRequests`) asks GitHub for
    /// `head=<owner>:<branch>`, the owner read from the branch's own
    /// remote, so a same-named branch tracking another fork never
    /// matches. A directory of your own never is: it borrows the
    /// sidebar repository's path, so its branch may belong to anything.
    func checkoutPath(for summary: PullRequestSummary) -> String {
        let holders = worktrees(holding: summary)
            .filter { worktree in
                worktree.isHostDirectory == false
                    && pullRequests.branchSummary(repositoryPath: repository.path, branch: worktree.branch)?.number
                    == summary.number
            }
            .map(\.path)
        return holders.first { $0 == worktreePath } ?? holders.first ?? repository.path
    }

    private func worktrees(holding summary: PullRequestSummary) -> [Worktree] {
        items.map(\.worktree).filter { $0.repositoryPath == repository.path && $0.branch == summary.headBranch }
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
