import SanductorDomain

extension MobileSession {
    func sidebarStatus() -> SidebarStatus {
        sidebarStatus(inactiveStatus: .branch, hasUnpushedCommits: isAhead)
    }

    private var isAhead: Bool {
        (gitStatus?.aheadOfUpstream ?? 0) > 0
    }

    private func sidebarStatus(inactiveStatus: SidebarStatus, hasUnpushedCommits: Bool) -> SidebarStatus {
        .status(
            session: AgentSession(name: name, agent: agent, status: .running, activity: activity),
            pullRequest: nil,
            inactiveStatus: inactiveStatus,
            hasUnpushedCommits: hasUnpushedCommits,
        )
    }

    func sidebarEntry(in sidebar: [SidebarRepository]) -> SidebarEntry? {
        guard let projected = sidebar.first(where: { group in
                  SessionName.slug(group.name) == repository && group.entries.contains { $0.target.path == directory }
              }),
              let entry = projected.entries.first(where: { $0.target.path == directory })
        else {
            return nil
        }

        let target = SidebarTarget(
            repository: entry.target.repository,
            repositoryPath: entry.target.repositoryPath,
            branch: branch,
            path: entry.target.path,
        )
        let block = entry.block.flatMap { $0.applies(to: target) ? $0 : nil }
        let inactive = SidebarStatus.inactiveStatus(for: target, defaultBranch: projected.defaultBranch)
        let matches = entry.target.branch == branch && (entry.paneID == nil || entry.paneID == id)
        let unpushed = entry.target.branch == branch ? entry.hasUnpushedCommits ?? isAhead : isAhead
        var status = block != nil ? SidebarStatus.blocked
            : matches && entry.activity == activity
            ? entry.status : sidebarStatus(inactiveStatus: inactive, hasUnpushedCommits: unpushed)
        if [.idleAgent, .worktree, .branch, .defaultBranch].contains(status) {
            status = agent == nil ? inactive : .idleAgent
        }
        return SidebarEntry(
            target: target,
            status: status,
            activity: activity,
            block: block,
            pullRequest: entry.target.branch == branch ? entry.pullRequest : nil,
            lastEventAt: matches ? entry.lastEventAt : nil,
            paneID: id,
            transcriptPath: matches ? entry.transcriptPath : nil,
        )
    }
}
