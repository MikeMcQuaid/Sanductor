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

    func startDiscussion(
        _ url: String,
        repository: Repository,
        context: String,
        agent: AgentKind,
        options: AgentLaunchOptions,
        worktree: Worktree? = nil,
        baseBranch: String? = nil,
        reveals: Bool = true,
    ) async {
        let draft = LaunchDraft(
            text: context, source: .discussion, agent: agent, options: options, base: baseBranch, discussionURL: url,
        )
        await run(
            draft,
            in: worktree == nil ? repository : nil,
            placeholder: worktree == nil ? "discussion" : nil,
            at: worktree?.path,
            reveals: reveals,
        ) { service in
            let prompt = try await github.discussionPrompt(repositoryPath: repository.path, url: url, context: context)
            if let worktree {
                return try await service.launchAgent(in: worktree, prompt: prompt, agent: agent, options: options)
            }
            return try await service.createSession(
                repository: repository, prompt: prompt, agent: agent, options: options, baseBranch: baseBranch,
            )
        }
    }
}
