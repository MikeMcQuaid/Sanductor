import Foundation

/// Where a local branch is checked out and what it was cut from,
/// which tell a stack's own branches from neighbours. Split from the
/// branches for length.
public extension GitClient {
    /// The worktree path holding each checked-out local branch.
    func branchHolders(worktreePath: String) async -> [String: String] {
        let result = try? await git(
            ["for-each-ref", "--format=%(refname:short)%09%(worktreepath)", "refs/heads"],
            in: worktreePath,
            allowFailure: true,
        )
        var holders = [String: String]()
        for line in (result?.standardOutput ?? "").split(separator: "\n") {
            // A branch no worktree holds has an empty path, so one field.
            let fields = line.split(separator: "\t", maxSplits: 1)
            if let branch = fields.first, let path = fields.dropFirst().first {
                holders[String(branch)] = String(path)
            }
        }
        return holders
    }

    internal func unmergedBranchTips(worktreePath: String, base: String) async throws -> [String: String] {
        let result = try await git(
            ["for-each-ref", "--no-merged=" + base, "--format=%(refname:lstrip=2)%09%(objectname)", "refs/heads"],
            in: worktreePath,
        )
        var tips = [String: String]()
        for line in result.standardOutput.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1)
            if let name = fields.first, let tip = fields.dropFirst().first {
                tips[String(name)] = String(tip)
            }
        }
        return tips
    }

    /// A branch cut from HEAD records its parent in this worktree's checkout history.
    internal func stackBranchOrigins(
        worktreePath: String, branch: String, base: String,
    ) async throws -> [(String, String)] {
        let history = try await git(["reflog", "show", "--format=%H%x09%gs", "HEAD", "--"], in: worktreePath)
            .standardOutput
            .split(separator: "\n")
        var origins = [(String, String)]()
        for (entry, previous) in zip(history, history.dropFirst()) {
            let fields = entry.split(separator: "\t", maxSplits: 1)
            let prefix = "checkout: moving from "
            guard let tip = fields.first, let message = fields.dropFirst().first,
                  tip == previous.prefix(while: { $0 != "\t" }), message.hasPrefix(prefix)
            else {
                continue
            }

            let names = message.dropFirst(prefix.count).components(separatedBy: " to ")
            if let parent = names.first, let child = names.dropFirst().first {
                origins.append((parent, child))
            }
        }
        let descendants = try await git(
            [
                "for-each-ref", "--contains=refs/heads/" + branch, "--no-merged=" + base,
                "--format=%(refname:lstrip=2)", "refs/heads",
            ],
            in: worktreePath,
        )
        .standardOutput
        .split(separator: "\n")
        for child in descendants.map(String.init) where child != branch {
            if let parent = await createdFrom(child, worktreePath: worktreePath) {
                origins.append((parent, child))
            }
        }
        return origins
    }

    /// The local branch `branch` was created from, as its reflog's
    /// first entry records it, or nil when it was cut from `HEAD`
    /// or the reflog no longer reaches back that far.
    func createdFrom(_ branch: String, worktreePath: String) async -> String? {
        let result = try? await git(
            ["reflog", "show", "--format=%gs", "refs/heads/" + branch, "--"],
            in: worktreePath,
            allowFailure: true,
        )
        let prefix = "branch: Created from "
        guard let first = (result?.standardOutput ?? "").split(separator: "\n").last, first.hasPrefix(prefix) else {
            return nil
        }

        let source = String(first.dropFirst(prefix.count))
        guard source != "HEAD" else {
            return nil
        }

        return source.hasPrefix("refs/heads/") ? String(source.dropFirst("refs/heads/".count)) : source
    }
}
