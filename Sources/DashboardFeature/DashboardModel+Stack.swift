import Foundation
import SanductorData
import SanductorDomain
import TerminalUI

/// The stacks the sidebar knows about. GitHub's own chain of pull
/// requests says where a branch stands once they are open and based
/// on each other; until then the only thing that knows is git, so a
/// stack is derived from the worktree itself and kept for the row to
/// read. Deriving costs a handful of git calls per worktree, so it
/// happens a few worktrees at a time on a slow rota rather than in
/// every poll.
extension DashboardModel {
    /// Derives the stacks that are due, oldest answers first.
    func refreshStacks(of listed: [RepositoryGroup]) async {
        let selectedRepository = selection?.worktree.repositoryPath
        let ready = listed
            .flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .filter { (nextStackDerivation[$0.worktree.path] ?? .distantPast) <= Date() }
        // What is on screen first: the selected repository's rows
        // are the ones whose missing marker is noticed. A partition
        // rather than a sort, which needs an ordering of every pair
        // and had none to give.
        let onScreen = ready.filter { $0.worktree.repositoryPath == selectedRepository }
        let due = (onScreen + ready.filter { $0.worktree.repositoryPath != selectedRepository })
            .prefix(Self.stacksPerRefresh)
        // Each derivation is its own handful of git calls; the due
        // ones run beside each other rather than in a line.
        let derived = await withTaskGroup(of: (String, BranchStack).self) { tasks in
            for item in due {
                let previous = knownStackBranches(for: item)
                let merged = pullRequest(for: item)?.state == "MERGED"
                let base = baseRef(for: item)
                tasks.addTask {
                    let worktree = item.worktree
                    let stack = await self.service.stack(for: worktree)
                    guard let base, merged || previous.count > 1 && stack.isStacked == false else {
                        return (worktree.path, stack)
                    }

                    let known = previous + stack.branches
                    let remaining = try? await self.service.unfinishedStackBranches(
                        for: worktree, into: base, knownBranches: known, verifyGitHub: merged,
                    )
                    return (worktree.path, Self.remainingStack(
                        stack, branch: worktree.branch, known: known, remaining: remaining ?? known,
                    ))
                }
            }
            var collected = [(String, BranchStack)]()
            for await result in tasks {
                collected.append(result)
            }
            return collected
        }
        for (path, stack) in derived {
            derivedStacks[path] = stack
            // A branch standing on its own is the common case and
            // the cheap answer to be wrong about for a while, so it
            // is asked about far less often than a real stack. The
            // watcher marks a worktree due the moment its repository
            // moves, so both timers only catch a lost event; timed
            // alone, the rota was a process every ten seconds all
            // night for stacks that had not moved.
            let interval = RefreshCadence.slowed(
                stack.isStacked ? Self.stackInterval : Self.loneInterval,
                onBattery: isOnBattery(),
            )
            nextStackDerivation[path] = Date().addingTimeInterval(interval)
        }
    }

    nonisolated static func remainingStack(
        _ stack: BranchStack, branch: String, known: [String], remaining: [String],
    ) -> BranchStack {
        let pending = Set(remaining).union([branch])
        var seen = Set<String>()
        let branches = (known + [branch] + remaining).filter { pending.contains($0) && seen.insert($0).inserted }
        return BranchStack(
            base: stack.base,
            branches: branches,
            checkedOut: branch,
            stackingBlocker: stack.stackingBlocker,
            published: stack.published,
        )
    }

    func keepUnfinishedStack(_ branches: [String], for item: WorktreeItem) -> SessionService.CleanupRefusal {
        let worktree = item.worktree
        let known = knownStackBranches(for: item)
        let stack = derivedStacks[worktree.path] ?? BranchStack(
            base: groups.group(holding: item)?.defaultBranch, branches: known, checkedOut: worktree.branch,
        )
        derivedStacks[worktree.path] = Self.remainingStack(
            stack, branch: worktree.branch, known: known, remaining: branches,
        )
        cacheSidebar(groups)
        ErrorLog.shared.note(
            "Worktree kept for unfinished stack branches: " + branches.joined(separator: ", "),
            about: worktree.repositoryName,
            branch: worktree.branch,
        )
        return .unfinishedStack(branches)
    }

    func advanceMergedStack(_ item: WorktreeItem, merged: PullRequestSummary) async -> Bool {
        let worktree = item.worktree
        guard let base = baseRef(for: item), item.session?.isBusy != true, item.isDirty == false else {
            return false
        }

        var branches = knownStackBranches(for: item)
        if branches.count == 1 {
            branches = await service.stack(for: worktree).branches
        }
        guard let index = branches.firstIndex(of: worktree.branch), index + 1 < branches.count,
              let remaining = try? await service.unfinishedStackBranches(
                  for: worktree, into: base, knownBranches: branches, verifyGitHub: true,
              ),
              let next = branches.dropFirst(index + 1).first(where: remaining.contains)
        else {
            return false
        }

        let switched = try? await service.switchAfterMerge(worktree, to: next, tip: merged.headCommit, base: base) {
            guard let live = self.groups.flatMap(\.items).first(where: { $0.id == item.id }) else {
                return false
            }

            return live.worktree.branch == worktree.branch && live.session?.isBusy != true
                && self.deletingPaths.contains(item.id) == false
        }
        guard switched == true else {
            return false
        }

        let remembered = StackSelection.branch(for: worktree.path)
        if remembered == nil || remembered == worktree.branch {
            StackSelection.remember(next, for: worktree.path)
        }
        rename(item, to: next)
        if selection?.id == item.id {
            selection = item.renamed(branch: next)
        }
        nextStackDerivation[worktree.path] = nil
        pendingImmediateGitRead = true
        followUpDue = true
        return true
    }

    func knownStackBranches(for item: WorktreeItem) -> [String] {
        guard let stack = derivedStacks[item.worktree.path], stack.branches.contains(item.worktree.branch) else {
            return [item.worktree.branch]
        }

        return stack.branches
    }

    func unfinishedMergeBranches(for item: WorktreeItem) -> [String] {
        guard pullRequest(for: item)?.state == "MERGED" else {
            return []
        }

        return knownStackBranches(for: item).filter { $0 != item.worktree.branch }
    }

    /// The stack git says this worktree holds, when it holds one.
    func derivedStanding(for item: WorktreeItem) -> StackStanding? {
        guard let stack = derivedStacks[item.worktree.path], stack.isStacked,
              let position = stack.branches.firstIndex(of: item.worktree.branch).map({ $0 + 1 })
        else {
            return nil
        }

        return StackStanding(
            position: position,
            height: stack.branches.count,
            base: stack.parent(of: item.worktree.branch),
        )
    }

    // MARK: Private

    /// How long a derived stack is trusted before being asked again
    /// (Settings can change it; a lone branch waits five times as
    /// long), and how many worktrees one refresh will derive.
    static var stackInterval: TimeInterval {
        AppSettings.stackInterval
    }

    private static var loneInterval: TimeInterval {
        stackInterval * loneMultiplier
    }

    private static let loneMultiplier: TimeInterval = 60

    private static let stacksPerRefresh = 8
}
