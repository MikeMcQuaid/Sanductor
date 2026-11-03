import SanductorDomain

public extension PullRequestStore {
    /// Persists the decision before the UI presents a finding as resolved.
    func setOutsideDiffResolved(
        _ thread: ReviewThread, resolved: Bool, repositoryPath: String, number: Int?,
    ) throws {
        guard thread.outsideDiffReviewID != nil else {
            return
        }
        guard let number else {
            throw SessionServiceError("The pull request is still loading. Try resolving this finding again shortly.")
        }

        let key = AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number)
        try store.updatePersisting { metadata in
            if resolved {
                metadata.resolvedOutsideDiff[key, default: []].insert(thread.id)
            } else {
                metadata.resolvedOutsideDiff[key]?.remove(thread.id)
                if metadata.resolvedOutsideDiff[key]?.isEmpty == true {
                    metadata.resolvedOutsideDiff[key] = nil
                }
            }
        }
    }

    /// Applies local decisions in memory without refreshing GitHub or changing inline threads.
    func applyingOutsideDiffResolutions(
        to threads: [ReviewThread], repositoryPath: String, number: Int,
    ) -> [ReviewThread] {
        let resolved = store.load().resolvedOutsideDiff[
            AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number), default: [],
        ]
        return threads.map { thread in
            var thread = thread
            if thread.outsideDiffReviewID != nil {
                thread.isResolved = resolved.contains(thread.id)
            }
            return thread
        }
    }
}
