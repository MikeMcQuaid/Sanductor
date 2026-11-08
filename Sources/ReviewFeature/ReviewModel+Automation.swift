import SanductorData
import SanductorDomain
import TerminalUI

extension ReviewModel {
    /// Flips one conversation's resolved state on GitHub, then
    /// refreshes the inline listing.
    func toggleResolved(_ thread: ReviewThread) async {
        do {
            let number = threadPullRequestNumber
            try await setThreadResolved(thread, thread.isResolved == false, number)
            if thread.outsideDiffReviewID != nil {
                if threadPullRequestNumber == number, let index = threads.firstIndex(where: { $0.id == thread.id }) {
                    threads[index].isResolved = thread.isResolved == false
                }
                UtilityTabTarget.resolutionMarksChanged()
            } else {
                await reloadThreads()
            }
        } catch {
            report(error.localizedDescription)
        }
        hasLoaded = true
    }

    func reloadThreads() async {
        let loaded = await fetchThreads()
        guard Task.isCancelled == false else {
            return
        }

        (threadPullRequestNumber, threads) = loaded
    }

    func reapplyOutsideDiffResolutions(pullRequests: PullRequestStore, repositoryPath: String) {
        guard let number = threadPullRequestNumber else {
            return
        }

        threads = pullRequests.applyingOutsideDiffResolutions(
            to: threads, repositoryPath: repositoryPath, number: number,
        )
    }

    func toggleResolveOnPush(_ thread: ReviewThread) async {
        do {
            try await resolveOnPush?(thread)
            UtilityTabTarget.resolutionMarksChanged()
        } catch {
            report(error.localizedDescription)
        }
    }

    func configureResolveOnPush(worktree: Worktree, pullRequests: PullRequestStore) {
        let currentSummary = { [weak self] () -> PullRequestSummary? in
            if let number = self?.threadPullRequestNumber,
               let summary = pullRequests.cachedSummary(repositoryPath: worktree.repositoryPath, number: number)
            {
                return summary
            }
            guard let summary = pullRequests.cachedListing(
                repositoryPath: worktree.repositoryPath, scope: .branch(worktree.branch),
            )?
                .first(where: { summary in
                    self?.threadPullRequestNumber.map { $0 == summary.number } ?? (summary.state == "OPEN")
                })
            else {
                return nil
            }

            return pullRequests.cachedSummary(
                repositoryPath: worktree.repositoryPath, number: summary.number,
            ) ?? summary
        }
        resolveOnPush = { [weak self] thread in
            guard let summary = currentSummary() else {
                self?.report("The pull request is still loading. Try marking this conversation again shortly.")
                return
            }

            try await pullRequests.toggleResolveOnPush(
                repositoryPath: worktree.repositoryPath,
                summary: summary,
                thread: thread,
            )
        }
        pendingResolution = { thread in
            currentSummary().map { pullRequests.pendingResolution(pullRequestURL: $0.url, threadID: thread.resolveID) }
                ?? false
        }
        resolveReviews = { [weak self] threads, review in
            for failure in await pullRequests.resolveReviews(
                threads,
                repositoryPath: worktree.repositoryPath,
                number: self?.threadPullRequestNumber,
                summary: currentSummary(),
                local: review.map { (worktree.path, $0) },
            ) {
                self?.report(failure)
            }
            UtilityTabTarget.resolutionMarksChanged()
            if review != nil {
                UtilityTabTarget.pullRequestCacheChanged()
            }
        }
    }
}
