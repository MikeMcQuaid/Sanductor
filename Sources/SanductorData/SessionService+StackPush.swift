import SanductorDomain

extension SessionService {
    func pushStack(
        worktree: Worktree, stack: BranchStack, busyWorktrees: @Sendable () async -> Set<String>,
    ) async throws -> [String] {
        let queued = try await pullRequests.queuedBranches(repositoryPath: worktree.repositoryPath)
        let (index, branches) = try stackPushSelection(
            worktree: worktree, stack: stack, queued: queued,
        )
        guard let first = branches.first else {
            return []
        }

        let path = worktree.path
        let remote = await forkRemote(worktreePath: path, branch: first)?.remote ?? "origin"
        var fixedParent: (branch: String, previousTip: String)?
        if let below = stack.parent(of: first), queued.contains(below),
           let tip = await git.commitHash(of: below, worktreePath: path)
        {
            fixedParent = await (remoteBranchRef(worktreePath: path, branch: below), tip)
        }

        let pushed = try await git.withRemoteOperation(worktreePath: path) { [fixedParent] in
            try await git.git(["fetch", "--prune", remote], in: path, remote: remote)
            let refs = try await prepareStackPush(
                branches: (branches, Set(stack.branches.dropFirst(index + 1))),
                parent: fixedParent,
                path: path,
                remote: remote,
                busyWorktrees: busyWorktrees,
            )
            let pushed = refs.map(\.branch)
            if pushed.isEmpty == false {
                let needsUpstream = try await git.branchesNeedingUpstream(pushed, remote: remote, in: path)
                await progress("Pushing " + pushed.joined(separator: ", "))
                try await git.git(
                    ["push", "--atomic"] + refs.map { "--force-with-lease=refs/heads/" + $0.branch + ":" + $0.lease }
                        + [remote] + refs.map { $0.tip + ":refs/heads/" + $0.branch },
                    in: path,
                    remote: remote,
                )
                for branch in needsUpstream {
                    let upstream = "refs/remotes/" + remote + "/" + branch
                    try await git.git(["branch", "--set-upstream-to=" + upstream, branch], in: path)
                }
            }
            return pushed
        }
        pullRequests.markChecksPending(repositoryPath: worktree.repositoryPath, branches: pushed)
        return pushed
    }

    private struct StackPushRef {
        let branch: String
        let lease: String
        let tip: String
    }

    private func prepareStackPush(
        branches: (selected: [String], publishedOnly: Set<String>),
        parent: (branch: String, previousTip: String)?,
        path: String,
        remote: String,
        busyWorktrees: @Sendable () async -> Set<String>,
    ) async throws -> [StackPushRef] {
        var refs = [StackPushRef]()
        var parent = parent
        for branch in branches.selected {
            let lease = await git.commitHash(of: "refs/remotes/" + remote + "/" + branch, worktreePath: path)
            if lease == nil, branches.publishedOnly.contains(branch) {
                continue
            }
            let previous = await git.commitHash(of: branch, worktreePath: path)
            _ = try await git.preparePush(
                worktreePath: path,
                branch: branch,
                remote: remote,
                parent: parent?.branch,
                fetchedTip: lease ?? "",
                busyWorktrees: busyWorktrees,
            )
            try await git.integratePushParent(parent, branch: branch, worktreePath: path, busyWorktrees: busyWorktrees)
            guard let tip = await git.commitHash(of: branch, worktreePath: path) else {
                throw stackError("Cannot read the tip of " + branch, in: path)
            }

            if AppSettings.requiresSignedCommits, tip != lease,
               await git.isCommitSigned(worktreePath: path, ref: tip) == false
            {
                throw SessionServiceError(
                    branch + "'s tip commit is not GPG signed; Rebase signs the stack before pushing.",
                )
            }
            refs.append(StackPushRef(branch: branch, lease: lease ?? "", tip: tip))
            parent = previous.map { (branch, $0) }
        }
        return refs
    }

    private func stackPushSelection(
        worktree: Worktree, stack: BranchStack, queued: Set<String>,
    ) throws -> (Int, [String]) {
        if stack.isStacked {
            try requireStackable(stack)
        }
        guard let index = stack.branches.firstIndex(of: worktree.branch) else {
            throw stackError("The selected branch is no longer in the stack", in: worktree.path)
        }

        let movable = stack.mutableBranches(queued: queued)
        return (index, stack.branchesToPush(through: worktree.branch)
            .filter(movable.contains))
    }
}
