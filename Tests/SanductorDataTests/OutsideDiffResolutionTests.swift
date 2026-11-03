import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct OutsideDiffResolutionTests {
    @Test
    func `local resolutions survive restart cache expiry and repeated reviews`() throws {
        let root = try TestSupport.temporaryDirectory("outside-diff-resolution")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let metadata = MetadataStore(file: root + "/state.json")
        let runner = CountingRunner()
        let github = GitHubClient(runner: runner)
        let store = PullRequestStore(github: github, store: metadata)
        let key = PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)
        let body = """
        <details><summary>Outside diff range comments (1)</summary>

        **file.swift:42**: Check this finding.

        </details>
        """
        func cache(_ body: String, reviewID: Int = 7) {
            metadata.update { value in
                value.conversationCache[key] = CachedConversation(events: [
                    ReviewComment(
                        id: reviewID, author: "coderabbitai[bot]", body: body, kind: "COMMENTED", authorType: "Bot",
                    ),
                ])
            }
        }
        cache(body)
        let finding = try #require(store.cachedConversation(repositoryPath: "/repo", number: 7).reviewThreads.first)
        try store.setOutsideDiffResolved(finding, resolved: true, repositoryPath: "/repo", number: 7)
        #expect(store.cachedConversation(repositoryPath: "/repo", number: 7).reviewThreads.first?.isResolved == true)
        #expect(store.applyingOutsideDiffResolutions(to: [finding], repositoryPath: "/repo", number: 8) == [finding])
        #expect(store.applyingOutsideDiffResolutions(to: [finding], repositoryPath: "/other", number: 7) == [finding])

        metadata.update { $0.conversationCache = [:] }
        let restoredPath = root + "/restored.json"
        try FileManager.default.copyItem(atPath: root + "/state.json", toPath: restoredPath)
        let restored = PullRequestStore(github: github, store: MetadataStore(file: restoredPath))
        #expect(restored.applyingOutsideDiffResolutions(
            to: [finding], repositoryPath: "/repo", number: 7,
        )
        .first?
        .isResolved == true)

        cache(body, reviewID: 8)
        #expect(store.cachedConversation(repositoryPath: "/repo", number: 7).reviewThreads.first?.isResolved == true)
        cache(body.replacing("Check this finding.", with: "Changed finding."), reviewID: 9)
        #expect(store.cachedConversation(repositoryPath: "/repo", number: 7).reviewThreads.first?.isResolved == false)
        cache(body, reviewID: 10)
        try store.setOutsideDiffResolved(finding, resolved: false, repositoryPath: "/repo", number: 7)
        #expect(store.cachedConversation(repositoryPath: "/repo", number: 7).reviewThreads.first?.isResolved == false)
        #expect(metadata.load().resolvedOutsideDiff.isEmpty)
        #expect(runner.calls == 0)
    }
}
