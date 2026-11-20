import Foundation
import SanductorDomain

public extension SessionService {
    /// A background launch shares the normal sandbox funnel without
    /// writing into a foreground launch's progress. Retries reuse its worktree.
    func launchScheduledPrompt(_ prompt: SavedPrompt, due: Date) async throws -> String {
        let service = reporting(to: silentLaunchReporter)
        let repository = Repository(
            name: URL(filePath: prompt.repositoryPath).lastPathComponent,
            path: prompt.repositoryPath,
        )
        try requireSandboxWorkspace(repository.path)
        let branch = prompt.branch(for: due)
        let worktrees = try await git.worktrees(of: repository)
        let existing = worktrees.first { $0.branch == branch }
        if let existing, await hasLiveSession(worktreePath: existing.path) {
            return SessionName.make(repository: repository.name, branch: branch, agent: prompt.agent)
        }
        let prepared = try await preparePrompt(prompt.prompt)
        let path: String =
            if let existing {
                existing.path
            } else {
                try await git.withRemoteOperation(worktreePath: repository.path) {
                    try await service.createWorktreePath(repository: repository, branch: branch)
                }
            }
        return try await service.start(
            prompt: prepared,
            agent: prompt.agent,
            options: AgentLaunchOptions(
                model: prompt.model.isEmpty ? nil : prompt.model,
                effort: prompt.effort.isEmpty ? nil : prompt.effort,
            ),
            slot: WorktreeSlot(repository: repository, branch: branch, path: path),
        )
    }
}
