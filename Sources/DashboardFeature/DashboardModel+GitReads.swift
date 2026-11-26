import Foundation
import SanductorData
import SanductorDomain

/// When the sidebar asks git about each repository: when the file
/// system says something under it changed, with slow safety re-reads
/// in case an event was lost. Blind cadence read twenty-nine
/// repositories' git for rows that never changed; an idle workspace
/// now reads almost nothing.
extension DashboardModel {
    /// The safety intervals under a running watcher, and the old
    /// time-based cadence for a machine whose watcher could not
    /// start. Seconds.
    static let selectedGitInterval: TimeInterval = 60
    static let idleGitInterval: TimeInterval = 300
    static let unwatchedSelectedInterval: TimeInterval = 0
    static let unwatchedIdleInterval: TimeInterval = 30

    /// The repositories whose git is read this tick: any asked for
    /// by name, any the watcher saw change, and any past its safety
    /// interval. Everything before the first reading lands.
    func gitReadScope(forcing paths: Set<String>, immediately: Bool = false) -> GitReadScope {
        let now = Date()
        guard hasLoaded else {
            lastGitReadAt = now
            for group in groups {
                gitReadAt[group.repository.path] = now
            }
            return .all
        }

        let onBattery = isOnBattery()
        let minimumInterval = RefreshCadence.pollSeconds(
            setting: Self.pollInterval, visible: isWindowVisible, onBattery: onBattery,
        )
        if immediately == false, paths.isEmpty, onBattery || isWindowVisible == false,
           now.timeIntervalSince(lastGitReadAt) < Double(minimumInterval)
        {
            return .only([])
        }

        let changed = watcher.consumeChangedPaths()
        let watching = watcher.isWatching
        var due = paths
        let selectedRepository = selection?.worktree.repositoryPath
        for group in groups {
            let path = group.repository.path
            let isSelected = path == selectedRepository
            let interval = watching
                ? (isSelected ? Self.selectedGitInterval : Self.idleGitInterval)
                : (isSelected ? Self.unwatchedSelectedInterval : Self.unwatchedIdleInterval)
            let last = gitReadAt[path] ?? .distantPast
            // A repository whose `.git` something wrote under is due
            // a stack derivation for each of its worktrees: every
            // ref lives there, a linked worktree's included, so
            // nothing moves a branch without the watcher seeing it,
            // and the rota's own timers are a backstop for a lost
            // event rather than how a change is found. An agent
            // editing sources touches the repository without moving
            // anything, and marked every worktree due each tick.
            let refsMoved = changed.contains(path + "/.git")
            if refsMoved || paths.contains(path) {
                for item in group.items {
                    nextStackDerivation[item.worktree.path] = .distantPast
                }
            }
            let safety = RefreshCadence.slowed(interval, onBattery: onBattery)
            if now.timeIntervalSince(last) >= safety {
                due.insert(path)
            } else {
                due.formUnion(changed.compactMap { checkoutToRead(for: $0, in: group) })
            }
            if due.contains(path) {
                gitReadAt[path] = now
            }
        }
        if due.isEmpty == false {
            lastGitReadAt = now
        }
        return .only(due)
    }

    private func checkoutToRead(for change: String, in group: RepositoryGroup) -> String? {
        let repo = group.repository.path
        if change == repo || change.hasPrefix(repo + "/") || repo.hasPrefix(change + "/") {
            return repo
        }
        for item in group.items {
            let tree = item.worktree
            if change == tree.path || change.hasPrefix(tree.path + "/") {
                return tree.repositoryPath == repo && tree.isHostDirectory == false ? tree.path : repo
            }
        }
        // A container event can add or remove a worktree, including an unregistered clone.
        let container = service.worktreeContainer(repository: group.repository)
        return change == container || change.hasPrefix(container + "/") || container.hasPrefix(change + "/")
            ? repo : nil
    }
}
