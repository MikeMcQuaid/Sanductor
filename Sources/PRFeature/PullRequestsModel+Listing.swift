import SanductorDomain
import TerminalUI

/// What the tab is listing and how it asks for it. Split from the
/// model for length.
extension PullRequestsModel {
    /// Takes the cache's summary for the selected pull request and
    /// every listed row, so what the sidebar just learnt shows here
    /// too; the cache is written by whichever side fetched last.
    func repaintFromCache() {
        let listed = pullRequests.cachedListing(
            repositoryPath: repository.path,
            scope: scope.listScope(branch: listedBranch),
        ) ?? summaries
        let successor = successorOfMergedSelection(in: listed)
        summaries = Self.worthShowing(listed).map { row in
            withCachedUnresolved(pullRequests.cachedSummary(repositoryPath: repository.path, number: row.number) ?? row)
        }
        page = min(page, max(0, summaries.count - 1) / PullRequestListView.pageSize)
        if let successor {
            select(successor)
        } else if let selected {
            guard let listedSelection = summaries.first(where: { $0.number == selected.number }) else {
                self.selected = nil
                return
            }

            let cached = pullRequests.cachedSummary(repositoryPath: repository.path, number: selected.number)
                ?? listedSelection
            let painted = withCachedUnresolved(cached)
            if painted != selected {
                self.selected = painted
            }
        }
    }

    /// Mine and Open may drop a merged PR and retarget its child in the same refresh.
    private func successorOfMergedSelection(in fresh: [PullRequestSummary]) -> PullRequestSummary? {
        guard scope != .worktree, let selected, canHaveStackChildren(selected) else {
            return nil
        }

        let updated = fresh.first { $0.number == selected.number }
            ?? pullRequests.cachedSummary(repositoryPath: repository.path, number: selected.number)
        guard updated?.state == "MERGED" else {
            return nil
        }

        let children = summaries.filter { $0.state == "OPEN" && $0.baseBranch == selected.headBranch }
        guard children.count == 1, let child = children.first else {
            return nil
        }

        return fresh.first { $0.number == child.number && $0.state == "OPEN" }
    }

    /// The branch the tab lists and compares against: the checked
    /// out one when known, the worktree's recorded one otherwise.
    var listedBranch: String? {
        stacking.selected ?? currentBranch ?? branch
    }

    /// Follows the visible PR chain when the worktree has no local stack for this PR.
    func listedStack(containing summary: PullRequestSummary) -> BranchStack {
        let parents = listedParents(of: summary)
        var branches = parents.reversed().map(\.headBranch) + [summary.headBranch]
        let byBase = Dictionary(grouping: summaries.filter { $0.state == "OPEN" }, by: \.baseBranch)
        var current = summary
        while canHaveStackChildren(current), let children = byBase[current.headBranch],
              children.count == 1, let child = children.first, branches.contains(child.headBranch) == false
        {
            branches.append(child.headBranch)
            current = child
        }
        let base = (parents.last ?? summary).baseBranch
        return BranchStack(base: base.isEmpty ? nil : base, branches: branches, checkedOut: summary.headBranch)
    }

    /// Counts the selected layer and its open ancestors in the PR listing.
    func stackDepth(for summary: PullRequestSummary) -> Int {
        listedParents(of: summary).count + 1
    }

    private func listedParents(of summary: PullRequestSummary) -> [PullRequestSummary] {
        guard summary.state == "OPEN" else {
            return []
        }

        let byHead = Dictionary(grouping: summaries.filter { canHaveStackChildren($0) }, by: \.headBranch)
        var parents = [PullRequestSummary]()
        var current = summary
        var seen = Set([current.headBranch])
        while let candidates = byHead[current.baseBranch], candidates.count == 1, let parent = candidates.first,
              seen.insert(parent.headBranch).inserted
        {
            parents.append(parent)
            current = parent
        }
        return parents
    }

    private func canHaveStackChildren(_ summary: PullRequestSummary) -> Bool {
        let baseRepository = repository.fullName ?? GitHubRemote.fullName(ofURL: summary.url)
        return summary.state == "OPEN" && summary.headBranch != defaultBranch
            && (summary.headRepository == nil || summary.headRepository?.lowercased() == baseRepository?.lowercased())
    }

    /// What the listing on screen is of, so an answer that arrives
    /// after the tab has moved on is dropped rather than shown.
    var cacheKey: String {
        String(describing: scope) + "#" + (listedBranch ?? "")
    }

    /// The worktree listing, or nothing at all on the default
    /// branch: asking GitHub for a pull request whose head is
    /// `main` searches a repository's whole history of them to say
    /// what the branch itself already says, which on a large tap
    /// takes seconds every time the tab opens.
    func listing(limit: Int) async throws -> [PullRequestSummary] {
        guard scope != .worktree || listedBranch != defaultBranch else {
            return []
        }

        return try await fetchList(scope.listScope(branch: listedBranch), limit)
    }

    /// Fetches the listing up to `limit` and shows it; false when the
    /// tab moved to another scope or branch while it was asked, so
    /// the answer was dropped.
    func showListing(limit: Int) async throws -> Bool {
        // Captured before the await: a slow answer for an already
        // switched scope must neither show nor cache under the new
        // scope's key, and one a reload overtook must not replace
        // the reload's rows.
        let requested = cacheKey
        let generation = listingGeneration
        let fetched = try await listing(limit: limit)
        guard Task.isCancelled == false, requested == cacheKey, generation == listingGeneration else {
            return false
        }

        // As the caches took it: a pushed branch's row stays
        // pending until GitHub has caught up with the push.
        let kept = pullRequests.rememberListing(
            repositoryPath: repository.path,
            scope: scope.listScope(branch: listedBranch),
            summaries: fetched,
            limit: limit,
        )
        let successor = successorOfMergedSelection(in: kept)
        summaries = Self.worthShowing(kept)
        if let successor {
            select(successor)
        }
        fetchedLimit = max(limit, kept.count)
        return true
    }

    /// Moves to the next page, asking GitHub for one more page first
    /// when the last answer filled its limit and holds nothing for
    /// it. An answer with nothing further steps back to the last
    /// page that has rows.
    func showNextPage() async {
        let generation = listingGeneration
        page += 1
        let pageSize = PullRequestListView.pageSize
        guard hasMore, summaries.count <= page * pageSize else {
            return
        }

        isLoading = true
        defer {
            if generation == listingGeneration {
                isLoading = false
                page = min(page, max(0, summaries.count - 1) / pageSize)
            }
        }
        do {
            _ = try await showListing(limit: (page + 1) * pageSize)
        } catch where generation == listingGeneration {
            ServiceStatus.shared.record(failure: error, doing: "Pull requests for " + repository.name)
        } catch {
            // A reload overtook this fetch and answers for it.
        }
    }
}
