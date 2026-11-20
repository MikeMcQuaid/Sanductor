import Foundation
import SanductorData
import SanductorDomain

extension DashboardModel {
    struct SidebarState {
        let status: SidebarStatus
        let date: Date
        let needsPush: Bool
    }

    func repositoryGroups(sortedBy sort: RepositorySort) -> [RepositoryGroup] {
        sort.sorted(visibleGroups) { group in
            RepositorySort.Key(
                name: group.repository.fullName ?? group.repository.name,
                statuses: group.items.map { sidebarStatus(for: $0) },
                activity: SessionService.repositoryActivity(of: group),
            )
        }
    }

    var sidebarTargets: [SidebarTarget] {
        groups.flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .map { SidebarTarget($0.worktree) }
    }

    func block(for item: WorktreeItem) -> WorkBlock? {
        workBlocks.first { $0.applies(to: SidebarTarget(item.worktree)) }
    }

    func sidebarStatus(for item: WorktreeItem) -> SidebarStatus {
        sidebarState(for: item).status
    }

    var statusGroups: [(status: SidebarStatus, items: [WorktreeItem])] {
        let rows = visibleGroups.flatMap(\.items).map { (item: $0, state: sidebarState(for: $0)) }
        let grouped = Dictionary(grouping: rows.sorted { $0.state.date > $1.state.date }, by: \.state.status)
        return SidebarStatus.allCases.compactMap { status in
            grouped[status].map { (status, $0.map(\.item)) }
        }
    }

    func updateWorkBlocks() {
        let updated = store.load().workBlocks
        if workBlocks != updated {
            workBlocks = updated
        }
        cacheSidebar(groups)
    }

    func refreshWorkBlocks(force: Bool) async {
        guard workBlocks.isEmpty == false,
              force || Date().timeIntervalSince(blocksReadAt)
              >= RefreshCadence.slowed(PullRequestStore.minimumInterval, onBattery: isOnBattery())
        else {
            return
        }

        blocksReadAt = Date()
        await service.resolveWorkBlocks()
        updateWorkBlocks()
    }

    func refreshStatusDetails() async {
        await startStatusDetailsRefresh().value
    }

    @discardableResult
    func startStatusDetailsRefresh() -> Task<Void, Never> {
        if let statusDetailsTask {
            return statusDetailsTask
        }

        let task = Task {
            await readStatusDetails()
            statusDetailsTask = nil
        }
        statusDetailsTask = task
        return task
    }

    func sidebarState(for item: WorktreeItem) -> SidebarState {
        let pullRequest = pullRequest(for: item)
        let push = pullRequest == nil ? pullRequests.pendingPushAt(
            repositoryPath: item.worktree.repositoryPath, branch: item.worktree.branch,
        ) : pullRequest?.pendingPushAt
        let needsPush = item.needsPush(hasPullRequest: pullRequest != nil, lastPush: push)
        let status = SidebarStatus.status(
            session: item.session,
            pullRequest: pullRequest,
            inactiveStatus: .inactiveStatus(
                for: SidebarTarget(item.worktree), defaultBranch: groups.group(holding: item)?.defaultBranch,
            ),
            isHostDirectory: item.worktree.isHostDirectory,
            launchFailed: launchFailure(for: item) != nil,
            blocked: block(for: item) != nil,
            reviewThreadsKnown: pullRequest.map { summary in
                store.load().threadsCache[AppMetadata.threadsKey(
                    repositoryPath: item.worktree.repositoryPath, number: summary.number,
                )] != nil
            } ?? false,
            hasUnpushedCommits: needsPush,
            pendingPushAt: push,
        )
        let date = max(
            Date(timeIntervalSince1970: TimeInterval(item.lastActivityAt)),
            item.session?.lastActivityAt ?? .distantPast,
            pullRequest?.lastEventAt ?? push ?? .distantPast,
        )
        return SidebarState(status: status, date: date, needsPush: needsPush)
    }

    private func readStatusDetails() async {
        let before = groups.flatMap(\.items).map { pullRequest(for: $0) }
        let statuses = groups.flatMap(\.items).map { sidebarStatus(for: $0) }
        for item in groups.flatMap(\.items) {
            guard let summary = pullRequest(for: item), summary.state == "OPEN" else {
                continue
            }

            _ = try? await pullRequests.summary(repositoryPath: item.worktree.repositoryPath, number: summary.number)
            _ = try? await pullRequests.conversation(
                repositoryPath: item.worktree.repositoryPath,
                number: summary.number,
                seededBody: summary.body,
            )
        }
        if before != groups.flatMap(\.items).map({ pullRequest(for: $0) })
            || statuses != groups.flatMap(\.items).map({ sidebarStatus(for: $0) })
        {
            pullRequestCacheGeneration += 1
        }
        cacheSidebar(groups)
    }
}
