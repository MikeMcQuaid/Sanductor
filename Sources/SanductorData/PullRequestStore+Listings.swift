import Foundation
import SanductorDomain

extension PullRequestStore {
    func readListingIfDue(
        repositoryPath: String,
        scope: GitHubClient.ListScope,
        limit: Int,
        interval: TimeInterval,
        // Nil means the listing was already fresh.
        // swiftlint:disable:next discouraged_optional_collection
    ) async throws -> [PullRequestSummary]? {
        let key = Self.listingKey(repositoryPath: repositoryPath, scope: scope)
        // Paging past the last answer asks for rows no cache holds.
        let reachesFurther = limit > GitHubClient.listLimit
            && (store.load().pullRequestListsCache[key]?.summaries.count ?? 0) < limit
        guard reachesFurther || due(key, interval: interval) else {
            return nil
        }

        // A branch listing, the question the sidebar asks most, goes
        // conditional: GitHub answers an unchanged one with a 304,
        // which costs no rate limit, and the cache is what it was.
        // The other scopes are GraphQL, which has no entity tags.
        if case let .branch(branch) = scope {
            // The tag goes back only while the listing it stamped is
            // still here: caches are capped and age out, and a 304
            // against a listing the app no longer holds would report
            // a branch as having no pull request at all, for as long
            // as GitHub's answer stayed the same.
            let held = store.load()
            let cached = held.pullRequestListsCache[key]?.summaries
            let answer = try await github.branchPullRequests(
                repositoryPath: repositoryPath,
                branch: branch,
                etag: cached == nil ? nil : held.etags[key],
            )
            switch answer {
            case .unchanged:
                // An unchanged listing can still outdate a summary
                // enriched since it arrived.
                var kept = cached ?? []
                store.update { metadata in
                    metadata.fetchedAt[key] = Date()
                    kept = metadata.pullRequestListsCache[key]?.summaries ?? kept
                    Self.correctSummaries(in: &kept, repositoryPath: repositoryPath, metadata: &metadata)
                    metadata.pullRequestListsCache[key]?.summaries = kept
                }
                PerformanceLog.record(.cacheHit, "etag " + key, seconds: 0)
                return kept

            case let .changed(body, etag):
                var fetched = GitHubClient.summaries(fromRESTJSON: body)
                store.update { metadata in
                    fetched = Self.record(
                        fetched,
                        key: key,
                        repositoryPath: repositoryPath,
                        limit: GitHubClient.listLimit,
                        in: &metadata,
                    )
                    metadata.etags[key] = etag
                }
                return fetched
            }
        }

        var fetched = try await github.pullRequests(
            repositoryPath: repositoryPath,
            scope: scope,
            limit: limit,
            requiredChecks: requiredChecksReader(repositoryPath: repositoryPath),
        )
        store.update { metadata in
            fetched = Self.record(fetched, key: key, repositoryPath: repositoryPath, limit: limit, in: &metadata)
        }
        return fetched
    }

    /// Keeps a fetched listing as its key's answer, painted and
    /// stamped now, corrects the enriched summaries it outdates and
    /// hands it back as the caches took it. Every listing lands
    /// here, whichever side fetched it.
    static func record(
        _ fetched: [PullRequestSummary],
        key: String,
        repositoryPath: String,
        limit: Int,
        in metadata: inout AppMetadata,
    ) -> [PullRequestSummary] {
        var kept = painted(fetched, repositoryPath: repositoryPath, in: &metadata)
        correctSummaries(in: &kept, repositoryPath: repositoryPath, metadata: &metadata)
        // Invalidating the listing makes its next answer authoritative.
        if let previous = metadata.pullRequestListsCache[key]?.summaries,
           previous.count > max(limit, kept.count), metadata.fetchedAt[key] != nil
        {
            let numbers = Set(kept.map(\.number))
            kept += previous.filter { numbers.contains($0.number) == false }
        }
        metadata.pullRequestListsCache[key] = CachedPullRequestList(summaries: kept)
        metadata.fetchedAt[key] = Date()
        return kept
    }

    /// The row and the pane paint the enriched summary over the
    /// listing, and only open pull requests are enriched, so a
    /// listing is what notices one change state. One it reports
    /// merged or closed replaces a summary still calling it open;
    /// one it reports open again replaces the finished summary and clears its stamp,
    /// so the next enrichment asks rather than repeating the cache.
    static func correctSummaries(
        in listed: inout [PullRequestSummary],
        repositoryPath: String,
        metadata: inout AppMetadata,
    ) {
        for index in listed.indices {
            let key = summaryKey(repositoryPath: repositoryPath, number: listed[index].number)
            guard let cached = metadata.enrichedSummaryCache[key]?.summary else {
                continue
            }

            if listed[index].headRepository == nil, let headRepository = cached.headRepository {
                listed[index].headRepository = headRepository
            }
            let summary = listed[index]
            if summary.state == "OPEN" {
                if cached.state != "OPEN" {
                    metadata.enrichedSummaryCache[key] = CachedSummary(summary: summary, requiresHeadRefresh: true)
                    metadata.fetchedAt.removeValue(forKey: key)
                }
            } else if cached.state == "OPEN" {
                metadata.enrichedSummaryCache[key] = CachedSummary(summary: summary)
                metadata.pendingSince.removeValue(forKey: key)
            }
        }
    }
}
