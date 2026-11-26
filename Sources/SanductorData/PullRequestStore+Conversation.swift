import Foundation
import SanductorDomain

// MARK: - PullRequestConversation

/// One pull request's conversation as the pane shows it: its
/// description, what has been said since, and the review threads.
public struct PullRequestConversation: Sendable {
    // MARK: Public

    /// The pull request's description.
    public let body: String

    /// The reviews and comments, in the order they arrived.
    public let events: [ReviewComment]

    /// The review threads, from GraphQL when it answered.
    public let threads: [ReviewThread]

    /// Why GraphQL failed, nil when it answered; without it the
    /// missing resolve buttons look like a display bug.
    public let graphQLFailure: String?

    /// Inline threads and the latest CodeRabbit findings for display and copying.
    public var reviewThreads: [ReviewThread] {
        threads + outsideDiffThreads
    }

    // MARK: Internal

    let outsideDiffThreads: [ReviewThread]
}

/// The conversation half of the shared store: the same timer covers
/// a pull request's description, its comments and its threads, since
/// they are one screen and one question as far as anyone reading is
/// concerned.
public extension PullRequestStore {
    /// The conversation, fetched only when the last one is a minute
    /// old. `seededBody` is the description the listing already
    /// carries, which saves fetching it again.
    func conversation(
        repositoryPath: String,
        number: Int,
        seededBody: String?,
        interval: TimeInterval = minimumInterval,
    ) async throws -> PullRequestConversation {
        let key = Self.conversationKey(repositoryPath: repositoryPath, number: number)
        let threadsKey = AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number)
        let previousThreads = store.load().threadsCache[threadsKey]
        return try await Self.conversationReads.run(key: [store.file, key]) {
            guard due(key, interval: interval) else {
                return cachedConversation(repositoryPath: repositoryPath, number: number, seededBody: seededBody)
            }

            async let reviewThreads = github.conversationThreads(repositoryPath: repositoryPath, number: number)
            let (body, events) =
                if let seededBody {
                    try await (seededBody, github.reviewComments(repositoryPath: repositoryPath, number: number))
                } else {
                    try await github.conversation(repositoryPath: repositoryPath, number: number)
                }
            let answer = await reviewThreads
            var threads = answer.threads
            store.update { metadata in
                metadata.conversationCache[key] = CachedConversation(body: body, events: events)
                threads = metadata.threadsCache[threadsKey]?.applyingResolutions(since: previousThreads, to: threads)
                    ?? threads
                // A REST fallback never overwrites cached GraphQL threads:
                // that would strip the resolve buttons from a reopen.
                if answer.graphQLFailure == nil {
                    metadata.threadsCache[threadsKey] = CachedThreads(threads: threads)
                }
                metadata.fetchedAt[key] = Date()
            }
            return PullRequestConversation(
                body: body,
                events: events,
                threads: threads,
                graphQLFailure: answer.graphQLFailure,
                outsideDiffThreads: applyingOutsideDiffResolutions(
                    to: CodeRabbitOutsideDiff.threads(in: events), repositoryPath: repositoryPath, number: number,
                ),
            )
        }
    }

    /// Updates the resolution state of displayed threads while their conversation reloads.
    func applyingCachedResolutions(
        to threads: [ReviewThread], repositoryPath: String, number: Int,
    ) -> [ReviewThread] {
        let key = AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number)
        return applyingOutsideDiffResolutions(
            to: store.load().threadsCache[key]?.applyingResolutions(since: nil, to: threads) ?? threads,
            repositoryPath: repositoryPath,
            number: number,
        )
    }

    /// What the app already knows, for painting before anything is
    /// asked and for answering a question asked too soon.
    func cachedConversation(repositoryPath: String, number: Int, seededBody: String? = nil) -> PullRequestConversation {
        let metadata = store.load()
        let cached = metadata.conversationCache[Self.conversationKey(repositoryPath: repositoryPath, number: number)]
        return PullRequestConversation(
            body: seededBody ?? cached?.body ?? "",
            events: cached?.events ?? [],
            threads: metadata.threadsCache[AppMetadata.threadsKey(repositoryPath: repositoryPath, number: number)]?
                .threads ?? [],
            graphQLFailure: nil,
            outsideDiffThreads: applyingOutsideDiffResolutions(
                to: CodeRabbitOutsideDiff.threads(in: cached?.events ?? []),
                repositoryPath: repositoryPath,
                number: number,
            ),
        )
    }
}
