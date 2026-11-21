import SanductorDomain

extension GitClient {
    /// Divergent hashes and a pruned upstream can both hide an already published patch.
    func onlyPublishedChanges(in worktree: Worktree, facts: BranchFacts?, base: String?) async -> Bool {
        guard let facts, let fingerprint = facts.revision else {
            return false
        }

        if let ahead = facts.aheadOfUpstream {
            guard ahead > 0, (facts.behindUpstream ?? 0) > 0 else {
                return false
            }
        } else if (facts.ahead ?? 0) == 0 {
            return false
        }

        let branch = "refs/heads/" + worktree.branch
        let key = [fingerprint, branch, base ?? "", facts.upstream ?? ""].joined(separator: "\n")
        let cache = RepositoryFacts.shared
        if let known = await cache.pushStatus[worktree.path], known.revision == key {
            return known.published
        }

        do {
            let published: Bool
            if let upstream = facts.upstream, facts.aheadOfUpstream != nil {
                published = try await onlyPublishedPatches(branch, against: upstream, in: worktree.path)
            } else {
                // A pruned parent may still be reachable through a published child.
                let revisions = [branch, "--not", "--remotes"] + [base].compactMap(\.self)
                let novel = try await git(["rev-list", "--max-count=1"] + revisions, in: worktree.path)
                if novel.standardOutput.isEmpty == false, facts.upstream != nil, let base {
                    published = try await onlyPublishedPatches(branch, against: base, in: worktree.path)
                } else {
                    published = novel.standardOutput.isEmpty
                }
            }
            await cache.remember(published: published, at: worktree.path, revision: key)
            return published
        } catch {
            return false
        }
    }

    /// Ignore patch-equivalent commits after a restack and keep merge commits that genuinely differ.
    private func onlyPublishedPatches(
        _ branch: String, against upstream: String, in path: String,
    ) async throws -> Bool {
        let range = upstream + "..." + branch
        return try await git(["rev-list", "--max-count=1", "--right-only", "--cherry-pick", range], in: path)
            .standardOutput
            .isEmpty
    }
}
