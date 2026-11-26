import Foundation
import SanductorDomain

extension GitClient {
    /// The server checks this lease even when the tracking ref came from an earlier fetch.
    func pushKnownTip(branch: String, remote: String, worktreePath: String) async throws -> Bool {
        let tip = await commitHash(of: "refs/remotes/" + remote + "/" + branch, worktreePath: worktreePath) ?? ""
        if tip.isEmpty == false, await isAncestor(tip, of: branch, worktreePath: worktreePath) == false,
           await refWasBranchTip(worktreePath: worktreePath, branch: branch, ref: tip) == false
        {
            return false
        }
        do {
            try await sendBranch(branch, sourceCommit: nil, remote: remote, lease: tip, worktreePath: worktreePath)
            return true
        } catch let error as CommandError where error.result.standardOutput.contains("[rejected] (stale info)") {
            return false
        }
    }

    func sendBranch(
        _ branch: String, sourceCommit: String?, remote: String, lease: String, worktreePath: String,
    ) async throws {
        var arguments = ["push", "--porcelain", "--force-with-lease=refs/heads/" + branch + ":" + lease]
        if sourceCommit == nil,
           try await branchesNeedingUpstream([branch], remote: remote, in: worktreePath).isEmpty == false
        {
            arguments.append("--set-upstream")
        }
        try await git(
            arguments + [remote, sourceCommit.map { $0 + ":refs/heads/" + branch } ?? branch],
            in: worktreePath,
            remote: remote,
        )
    }

    /// Rewriting existing tracking settings wakes every worktree that shares the config.
    func branchesNeedingUpstream(_ branches: [String], remote: String, in path: String) async throws -> [String] {
        let output = try await git(
            ["for-each-ref", "--format=%(refname:strip=2)%09%(upstream:remotename)%09%(upstream:remoteref)"]
                + branches.map { "refs/heads/" + $0 },
            in: path,
        )
        let tracking = Set(output.standardOutput.split(separator: "\n"))
        return branches.filter { tracking.contains($0 + "\t" + remote + "\trefs/heads/" + $0) == false }
    }

    /// Captures the lease before rebasing, so later background fetches cannot change it.
    func preparePush(
        worktreePath: String,
        branch: String,
        remote: String,
        parent: String? = nil,
        fetchedTip: String? = nil,
        busyWorktrees: @Sendable () async -> Set<String> = { [] },
    ) async throws -> String {
        let tip: String
        if let fetchedTip {
            tip = fetchedTip
        } else {
            try await git(["fetch", "--prune", remote], in: worktreePath, remote: remote)
            tip = await commitHash(of: "refs/remotes/" + remote + "/" + branch, worktreePath: worktreePath) ?? ""
        }
        guard tip.isEmpty == false else {
            return ""
        }
        guard await isAncestor(tip, of: branch, worktreePath: worktreePath) == false,
              await refWasBranchTip(worktreePath: worktreePath, branch: branch, ref: tip) == false
        else {
            return tip
        }

        let base = await defaultBaseRef(of: Repository(name: "", path: worktreePath))
        if let currentParent = parent ?? base,
           await isAncestor(currentParent, of: branch, worktreePath: worktreePath),
           await isAncestor(currentParent, of: tip, worktreePath: worktreePath) == false
        {
            throw SessionServiceError(
                "Remote branch `\(remote)/\(branch)` has unseen commits "
                    + "and does not contain `\(currentParent)`.\n"
                    + "Integrate or explicitly resolve the remote history before pushing.",
            )
        }

        try await rebaseForPush(
            worktreePath: worktreePath, branch: branch, onto: tip, from: nil, busyWorktrees: busyWorktrees,
        )
        return tip
    }

    func integratePushParent(
        _ parent: (branch: String, previousTip: String)?,
        branch: String,
        worktreePath: String,
        busyWorktrees: @Sendable () async -> Set<String>,
    ) async throws {
        if let parent, await commitHash(of: parent.branch, worktreePath: worktreePath) != parent.previousTip,
           await isAncestor(parent.branch, of: branch, worktreePath: worktreePath) == false
        {
            try await rebaseForPush(
                worktreePath: worktreePath,
                branch: branch,
                onto: parent.branch,
                from: parent.previousTip,
                busyWorktrees: busyWorktrees,
            )
        }
    }

    /// Integrates in the branch's own worktree and restores whichever branch was selected.
    func rebaseForPush(
        worktreePath: String,
        branch: String,
        onto tip: String,
        from oldBase: String?,
        busyWorktrees: @Sendable () async -> Set<String>,
    ) async throws {
        let path = await branchHolders(worktreePath: worktreePath)[branch] ?? worktreePath
        guard await busyWorktrees().contains(where: { busy in
            URL(fileURLWithPath: busy).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }) == false else {
            throw SessionServiceError("`" + branch + "`'s agent is busy; push again once it is idle or done.")
        }

        let held = await currentBranch(worktreePath: path)
        guard let held else {
            throw SessionServiceError("Check out a branch before integrating remote work.")
        }

        try await preservingChanges(in: [path]) {
            do {
                if let oldBase {
                    try await rebaseSigned(branch: branch, onto: tip, from: oldBase, worktreePath: path)
                } else {
                    try await rebaseSigned(worktreePath: path, branch: branch, onto: tip)
                }
            } catch {
                if held != branch {
                    try? await checkout(branch: held, worktreePath: path)
                }
                throw error
            }
            if held != branch {
                try await checkout(branch: held, worktreePath: path)
            }
        }
    }
}
