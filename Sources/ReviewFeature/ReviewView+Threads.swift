import SanductorData
import SanductorDomain

extension ReviewView {
    static func reviewModel(
        worktree: Worktree, git: GitClient, github: GitHubClient, service: SessionService,
    ) -> ReviewModel {
        let pullRequests = service.pullRequestReads
        return ReviewModel(
            worktreePath: worktree.path,
            repositoryName: worktree.repositoryName,
            git: git,
            baseRefProvider: { await service.reviewBase(for: worktree) },
            draftMessage: { await service.draftCommitMessage(worktreePath: worktree.path) },
            fetchThreads: { await reviewThreads(worktree: worktree, git: git, pullRequests: pullRequests) },
            setThreadResolved: { thread, resolved, number in
                if thread.outsideDiffReviewID != nil {
                    try pullRequests.setOutsideDiffResolved(
                        thread, resolved: resolved, repositoryPath: worktree.repositoryPath, number: number,
                    )
                } else {
                    try await github.setThreadResolved(
                        repositoryPath: worktree.repositoryPath, threadID: thread.resolveID, resolved: resolved,
                    )
                }
            },
        )
    }

    private static func reviewThreads(
        worktree: Worktree, git: GitClient, pullRequests: PullRequestStore,
    ) async -> (number: Int?, threads: [ReviewThread]) {
        let branch = await git.currentBranch(worktreePath: worktree.path) ?? worktree.branch
        let listed = try? await pullRequests.listing(
            repositoryPath: worktree.repositoryPath, scope: .branch(branch),
        )
        guard let number = listed?.first(where: { $0.state == "OPEN" })?.number else {
            return (nil, [])
        }

        let answer = try? await pullRequests.conversation(
            repositoryPath: worktree.repositoryPath, number: number, seededBody: nil,
        )
        if let failure = answer?.graphQLFailure {
            PerformanceLog.recordMessage(
                "Conversations fell back to REST (no resolve buttons): " + failure, isError: false,
            )
        }
        return (number, answer?.reviewThreads ?? [])
    }
}
