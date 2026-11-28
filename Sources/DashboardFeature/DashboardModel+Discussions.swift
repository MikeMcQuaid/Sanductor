import SanductorData
import SanductorDomain

extension DashboardModel {
    func retryDiscussion(_ draft: LaunchDraft, repository: Repository, reveals: Bool, worktree: Worktree? = nil) async {
        guard let url = draft.discussionURL else {
            return
        }

        await startDiscussion(
            url,
            repository: repository,
            context: draft.text,
            agent: draft.agent,
            options: draft.options,
            worktree: worktree,
            baseBranch: draft.base,
            reveals: reveals,
        )
    }

    @discardableResult
    func startDiscussion(
        _ url: String,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions,
        worktree: Worktree? = nil,
        baseBranch: String? = nil,
        reveals: Bool = true,
    ) async -> LaunchFailure? {
        let draft = LaunchDraft(
            text: context, source: .discussion, agent: agent, options: options, base: baseBranch, discussionURL: url,
        )
        return await run(
            draft,
            in: worktree == nil ? repository : nil,
            placeholder: worktree == nil ? "discussion" : nil,
            at: worktree?.path,
            reveals: reveals,
        ) { service in
            let compose = try await github.discussionPrompt(repositoryPath: repository.path, url: url)
            if let worktree {
                return try await service.launchAgent(
                    in: worktree, prompt: context, agent: agent, options: options, composing: compose,
                )
            }
            return try await service.createSession(
                repository: repository,
                prompt: context,
                agent: agent,
                options: options,
                baseBranch: baseBranch,
                composing: compose,
            )
        }
    }
}
