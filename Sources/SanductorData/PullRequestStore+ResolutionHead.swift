import SanductorDomain

extension PullRequestStore {
    func summaryForResolution(repositoryPath: String, summary: PullRequestSummary) async throws -> PullRequestSummary {
        let key = Self.summaryKey(repositoryPath: repositoryPath, number: summary.number)
        if summary.state == "OPEN",
           let cached = store.load().enrichedSummaryCache[key], cached.summary.state != "OPEN"
        {
            try store.updatePersisting { metadata in
                guard let current = metadata.enrichedSummaryCache[key], current.summary.state != "OPEN" else {
                    return
                }

                metadata.enrichedSummaryCache[key] = CachedSummary(
                    summary: current.summary, savedAt: current.savedAt, requiresHeadRefresh: true,
                )
                metadata.fetchedAt.removeValue(forKey: key)
            }
        }
        let cached = store.load().enrichedSummaryCache[key]
        guard cached?.requiresHeadRefresh == true else {
            return cached?.summary ?? summary
        }
        guard let fresh = try await self.summary(
                  repositoryPath: repositoryPath, number: summary.number, interval: 0,
              ),
              store.load().enrichedSummaryCache[key]?.requiresHeadRefresh == false
        else {
            throw SessionServiceError("Could not refresh the reopened pull request's head. Try marking it again.")
        }

        return fresh
    }
}
