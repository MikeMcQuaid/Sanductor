import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension MetadataStoreTests {
    @Test
    func `overlapping initial loads return the winning legacy review identity`() throws {
        let root = try TestSupport.temporaryDirectory("overlapping-loads")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")
        var legacy = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [
            ReviewThread(id: "local", path: "file", line: 1, isResolved: false, comments: [], resolveID: ""),
        ])
        legacy.runID = nil
        var metadata = AppMetadata()
        metadata.localReviews["/worktree"] = legacy
        let data = try JSONEncoder().encode(metadata)
        let first = try JSONDecoder().decode(AppMetadata.self, from: data)
        let winner = try JSONDecoder().decode(AppMetadata.self, from: data)
        let loaded = store.load {
            #expect(store.load { winner } == winner)
            return first
        }
        #expect(loaded == winner)
        let review = try #require(loaded.localReviews["/worktree"])
        try PullRequestStore(github: GitHubClient(runner: CountingRunner()), store: store)
            .setLocalResolved("local", resolved: true, review: review, path: "/worktree")
        #expect(store.load().localReviews["/worktree"]?.remaining == 0)
    }
}
