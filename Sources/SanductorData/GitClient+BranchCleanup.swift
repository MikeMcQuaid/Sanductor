import Foundation
import SanductorDomain

/// Merge-safe branch deletion shared by worktree removal and repository sweeps.
public extension GitClient {
    /// Removes a clean worktree; the merged-branch sweep deletes its branch.
    func removeMergedWorktree(repository: Repository, worktreePath: String) async throws {
        try await git(["worktree", "remove", worktreePath], in: repository.path)
        try await git(["worktree", "prune"], in: repository.path)
    }

    /// Deletes merged branches regardless of stale upstreams, excluding
    /// the base, conventional default names and branches held by any worktree.
    @discardableResult
    func deleteMergedBranches(
        worktreePath: String, into ref: String,
    ) async throws -> (deleted: [String], failures: [String]) {
        let result = try await git(
            [
                "branch", "--merged", ref,
                "--format=%(if)%(worktreepath)%(then)%(else)%(objectname) %(refname)%(end)",
            ],
            in: worktreePath,
        )
        let base = Self.branchName(fromRef: ref)
        var deleted = [String]()
        var failures = [String]()
        for line in result.standardOutput.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard let tip = fields.first, let fullRef = fields.dropFirst().first,
                  fullRef.hasPrefix("refs/heads/")
            else {
                continue
            }

            let branch = String(fullRef.dropFirst("refs/heads/".count))
            guard ["main", "master", "trunk", base].contains(branch) == false else {
                continue
            }

            do {
                if try await deleteBranch(branch, at: String(tip), mergedInto: ref, worktreePath: worktreePath) {
                    deleted.append(branch)
                }
            } catch {
                failures.append("Cleaning merged branch `" + branch + "` failed: " + error.localizedDescription)
            }
        }
        return (deleted, failures)
    }

    /// Deletes only the verified tip after checking the current base and worktrees.
    internal func deleteBranch(
        _ branch: String, at tip: String, mergedInto baseRef: String, worktreePath: String,
    ) async throws -> Bool {
        try await withRemoteOperation(worktreePath: worktreePath) {
            try await deleteBranchWithoutLock(branch, at: tip, mergedInto: baseRef, worktreePath: worktreePath)
        }
    }

    private func deleteBranchWithoutLock(
        _ branch: String, at tip: String, mergedInto baseRef: String, worktreePath: String,
    ) async throws -> Bool {
        let ref = "refs/heads/" + branch
        let held = try await git(["for-each-ref", "--format=%(worktreepath)", ref], in: worktreePath)
        guard held.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              await isMerged(worktreePath: worktreePath, branch: tip, into: baseRef)
        else {
            return false
        }

        let deletion = try await git(
            ["update-ref", "--no-deref", "-d", ref, tip], in: worktreePath, allowFailure: true,
        )
        guard deletion.succeeded else {
            let current = try await git(
                ["rev-parse", "--verify", "--quiet", ref], in: worktreePath, allowFailure: true,
            )
            if current.status == 1 || current.succeeded
                && current.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) != tip
            {
                return false
            }
            throw CommandError(command: "git update-ref -d " + ref, result: deletion)
        }

        let configuration = try await git(
            ["config", "--local", "--remove-section", "branch." + branch],
            in: worktreePath,
            allowFailure: true,
            environment: ["LC_ALL": "C"],
        )
        guard configuration.succeeded || configuration.standardError.hasPrefix("fatal: no such section:") else {
            throw CommandError(
                command: "Removing configuration for deleted branch " + branch, result: configuration,
            )
        }

        return true
    }
}
