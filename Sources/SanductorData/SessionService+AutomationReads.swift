import SanductorDomain

extension SessionService {
    /// Reconciles only marked conversations for the pushed branches or the PR being refreshed.
    @preconcurrency
    public func resolveMarkedReviews(
        repositoryPath: String, branches: Set<String>, number: Int?, changed: @escaping @Sendable () async -> Void,
    ) async {
        let driver = automationDriver(groups: [])
        guard number != nil || branches.isEmpty == false else {
            return
        }

        await withDiscardingTaskGroup { group in
            for (key, state) in store.load().pullRequestAutomation where state.repositoryPath == repositoryPath
                && state.localWorktreePath == nil && state.resolutions.isEmpty == false
            {
                if let number, state.number != number {
                    continue
                }
                if let cached = pullRequests.cachedSummary(repositoryPath: repositoryPath, number: state.number),
                   cached.headBranch.isEmpty == false, branches.isEmpty == false,
                   branches.contains(cached.headBranch) == false
                {
                    continue
                }
                let context = AutofixContext(key: key, store: store, driver: driver, resolutionChanged: changed)
                group.addTask {
                    do {
                        try await autofixCoordinator.resolveAfterPush(
                            state: state, context: context, branches: branches,
                        )
                    } catch {
                        // The dashboard retries outstanding marks on its next refresh.
                        PerformanceLog.recordMessage(
                            "Checking marked review conversations: " + error.localizedDescription,
                            isError: false,
                        )
                    }
                }
            }
        }
    }

    func automationSummary(_ state: PullRequestAutomation, fresh: Bool) async throws -> PullRequestSummary? {
        if state.localWorktreePath != nil {
            return await localAutofixSummary(state)
        }
        if fresh {
            return try await github.pullRequestSummary(
                repositoryPath: state.repositoryPath,
                number: state.number,
                requiredChecks: pullRequests.requiredChecksReader(repositoryPath: state.repositoryPath),
            )
        }
        return try await pullRequests.summary(repositoryPath: state.repositoryPath, number: state.number)
    }

    func automationThreads(_ state: PullRequestAutomation, fresh: Bool) async throws -> [ReviewThread] {
        if fresh {
            return try await github.reviewThreads(repositoryPath: state.repositoryPath, number: state.number)
        }
        let conversation = try await pullRequests.conversation(
            repositoryPath: state.repositoryPath, number: state.number, seededBody: "",
        )
        guard conversation.graphQLFailure == nil else {
            throw SessionServiceError("Waiting for GitHub review threads")
        }

        return conversation.threads
    }

    func automationReviewComments(_ state: PullRequestAutomation, fresh: Bool) async throws -> [ReviewComment] {
        if fresh {
            return try await github.reviewComments(repositoryPath: state.repositoryPath, number: state.number)
        }
        return try await pullRequests.conversation(
            repositoryPath: state.repositoryPath, number: state.number, seededBody: "",
        )
        .events
    }

    func automationWriters(_ state: PullRequestAutomation, authors: Set<String>, fresh: Bool) async -> Set<String> {
        var verified = Set<String>()
        for author in authors where await github.hasWriteAccess(
            login: author, repositoryPath: state.repositoryPath, fresh: fresh,
        ) {
            verified.insert(author)
        }
        return verified
    }

    static func automationTarget(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        groups: [RepositoryGroup],
    ) -> AutofixDriver.Target? {
        guard let group = groups.first(where: { $0.repository.path == state.repositoryPath }),
              let defaultBranch = group.defaultBranch, summary.headBranch != defaultBranch,
              let item = group.items.first(where: { item in
                  item.worktree.branch == summary.headBranch
                      && (state.localWorktreePath == nil || item.worktree.path == state.localWorktreePath)
              }),
              let session = item.session, session.status == .running, session.agent != nil,
              session.paneID != nil, item.worktree.isHostDirectory == false
        else {
            return nil
        }

        return AutofixDriver.Target(
            worktree: item.worktree,
            session: session,
            allowsUncommitted: state.attempt == nil,
        )
    }
}
