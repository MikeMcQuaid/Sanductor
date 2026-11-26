import SanductorDomain

public extension SessionService {
    /// The remaining work in a stack whose checked-out PR has merged.
    func unfinishedStackBranches(
        for worktree: Worktree, into baseRef: String, knownBranches: [String] = [], verifyGitHub: Bool = false,
    ) async throws -> [String] {
        let path = worktree.path
        let branch = worktree.branch
        guard branch != Self.branchName(fromBaseRef: baseRef) else {
            return []
        }

        let excluded = Set(excludedStackBranches(worktreePath: path) + [Self.branchName(fromBaseRef: baseRef)])
        let summaries = pullRequests.cachedQueueSummaries(repositoryPath: worktree.repositoryPath)
        var members = knownStackMembers(for: worktree, known: knownBranches, summaries: summaries)
        var children = Dictionary(grouping: summaries, by: \.baseBranch).mapValues { $0.map(\.headBranch) }
        members.subtract(excluded)
        let unmerged = try await git.unmergedBranchTips(worktreePath: path, base: baseRef)
        if unmerged.keys.contains(where: { members.contains($0) == false }) {
            let parents = try await git.stackBranchOrigins(worktreePath: path, branch: branch, base: baseRef)
            for (parent, child) in parents {
                children[parent, default: []].append(child)
            }
        }
        Self.addChildren(children, to: &members, excluding: excluded)
        let mergedNumbers = Set(summaries.filter { $0.state == "MERGED" }.map(\.number))
        var reviews = summaries
            .filter { $0.state != "OPEN" || mergedNumbers.contains($0.number) == false }
            .map { review in
                GitHubClient.StackReview(
                    state: review.state, headRefName: review.headBranch, headRefOid: review.headCommit,
                )
            }
        if verifyGitHub, let url = await git.remoteURL(named: "origin", worktreePath: path),
           url.hasPrefix("/") == false, url.hasPrefix("file:") == false, GitHubRemote.fullName(ofURL: url) != nil
        {
            reviews = try await github.stackReviews(
                repositoryPath: worktree.repositoryPath,
                branches: members.sorted(),
                registered: summaries.filter { $0.headBranch == branch && $0.stackStanding?.isStacked == true }
                    .max { $0.number < $1.number },
            )
            members.formUnion(reviews.map(\.headRefName))
            let current = try await git.unmergedBranchTips(worktreePath: path, base: baseRef)
            guard current == unmerged else {
                throw SessionServiceError("Branches changed during the stack check. Refresh before cleaning up.")
            }
        }
        members.subtract(excluded)
        return Self.remaining(in: members, branch: branch, tips: unmerged, reviews: reviews)
    }

    /// Advances a clean checkout still on the merged commit. Git also checks for a
    /// merge or rebase in progress, conflicting ignored files and other worktrees.
    func switchAfterMerge(
        _ worktree: Worktree,
        to branch: String,
        tip mergedTip: String?,
        base: String,
        isIdle: @escaping @MainActor @Sendable () -> Bool,
    ) async throws -> Bool {
        let path = worktree.path
        return try await git.withRemoteOperation(worktreePath: path) {
            let result = try await git.git(
                GitWorktreeStatus.arguments + ["--branch", "--untracked-files=normal", "--ignore-submodules=none"],
                in: path,
            )
            let status = GitWorktreeStatus(porcelain: result.standardOutput)
            guard status.branch == worktree.branch, status.isDirty == false,
                  let tip = await git.commitHash(of: "HEAD", worktreePath: path)
            else {
                return false
            }

            if let mergedTip {
                guard tip == mergedTip else {
                    return false
                }
            } else if await git.isMerged(worktreePath: path, branch: tip, into: base) == false {
                return false
            }
            guard await isIdle() else {
                return false
            }

            return try await git.git(
                ["switch", "--no-guess", "--no-overwrite-ignore", "--", branch], in: path, allowFailure: true,
            )
            .succeeded
        }
    }

    // MARK: Internal

    internal func mergeCleanupRefusal(
        for worktree: Worktree, baseRef: String, knownBranches: [String],
    ) async throws -> CleanupRefusal? {
        let wasStacked = knownBranches.count > 1 || pullRequests.branchSummary(
            repositoryPath: worktree.repositoryPath, branch: worktree.branch,
        )?.state == "MERGED"
        if wasStacked == false, try await git.hasUncommittedChanges(worktreePath: worktree.path) {
            return .dirty
        }
        guard let tip = await git.tip(of: "refs/heads/" + worktree.branch, worktreePath: worktree.path) else {
            return .unverified
        }

        let merged = await git.isMerged(worktreePath: worktree.path, branch: tip, into: baseRef)
        if merged || wasStacked {
            let unfinished = try await unfinishedStackBranches(
                for: worktree, into: baseRef, knownBranches: knownBranches, verifyGitHub: true,
            )
            guard unfinished.isEmpty else {
                return .unfinishedStack(unfinished)
            }
        }
        guard merged else {
            return .unmerged
        }
        guard await git.currentBranch(worktreePath: worktree.path) == worktree.branch,
              await git.commitHash(of: "HEAD", worktreePath: worktree.path) == tip,
              await git.isMerged(worktreePath: worktree.path, branch: tip, into: baseRef)
        else {
            return .unverified
        }
        guard try await git.hasUncommittedChanges(worktreePath: worktree.path) == false else {
            return .dirty
        }

        return nil
    }

    internal func canLeaveMergedBranch(
        _ worktree: Worktree, branch: String, base: String, known: [String], report: inout MergeCleanupReport,
    ) async -> Bool {
        do {
            report.unfinishedBranches = try await unfinishedStackBranches(
                for: worktree, into: base, knownBranches: known, verifyGitHub: true,
            )
            guard let current = await git.currentBranch(worktreePath: worktree.path),
                  current == branch || current == Self.branchName(fromBaseRef: base)
            else {
                report.failures.append("The checked-out branch changed before cleanup.")
                return false
            }

            let path = worktree.path
            if current == branch, await git.isMerged(worktreePath: path, branch: current, into: base) == false {
                report.notes.append("Kept " + current + " because it has commits outside the default branch.")
                return false
            }
            if try await git.hasUncommittedChanges(worktreePath: path) {
                report.notes.append("Kept " + current + " because it has uncommitted changes.")
                return false
            }
            return report.unfinishedBranches.isEmpty
        } catch {
            report.failures.append("Checking the stack before cleanup failed: " + error.localizedDescription)
            return false
        }
    }

    // MARK: Private

    private func knownStackMembers(
        for worktree: Worktree, known: [String], summaries: [PullRequestSummary],
    ) -> Set<String> {
        let metadata = store.load()
        let saved = metadata.cachedSidebar
            .first { $0.path == worktree.repositoryPath }?
            .worktrees
            .first { $0.path == worktree.path }
        let stacks = [known, saved?.stackBranches ?? [], metadata.stackFacts[worktree.path]?.facts.stack.branches ?? []]
        var members = Set(stacks.filter { $0.contains(worktree.branch) }.joined())
        members.insert(worktree.branch)
        let numbers = Set(summaries.filter { $0.headBranch == worktree.branch }.compactMap { $0.stackStanding?.number })
        for summary in summaries where summary.stackStanding?.number.map(numbers.contains) == true {
            members.insert(summary.headBranch)
        }
        return members
    }

    private static func remaining(
        in members: Set<String>, branch: String, tips: [String: String], reviews: [GitHubClient.StackReview],
    ) -> [String] {
        let open = Set(reviews.filter { $0.state == "OPEN" }.map(\.headRefName))
        let merged = Dictionary(grouping: reviews.filter { $0.state == "MERGED" }, by: \.headRefName)
        return members.filter { member in
            if open.contains(member) {
                return true
            }
            guard member != branch, let tip = tips[member] else {
                return false
            }

            return merged[member]?.contains { $0.headRefOid == tip } != true
        }
        .sorted()
    }

    private static func addChildren(
        _ children: [String: [String]], to members: inout Set<String>, excluding excluded: Set<String>,
    ) {
        var pending = Array(members)
        while let parent = pending.popLast() {
            for child in children[parent] ?? [] where child.isEmpty == false && excluded.contains(child) == false
                && members.insert(child).inserted
            {
                pending.append(child)
            }
        }
    }
}
