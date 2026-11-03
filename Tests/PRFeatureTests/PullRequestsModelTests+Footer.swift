import AppKit
@testable import PRFeature
@testable import SanductorData
import SanductorDomain
import SwiftUI
import TerminalUI
import Testing

extension PullRequestsModelTests {
    @Test
    func `reviews footer updates when only local resolution marks change`() async throws {
        let model = makeModel()
        model.selected = summary(7, head: "feature")
        model.store.update { metadata in
            metadata.conversationCache[PullRequestStore.conversationKey(repositoryPath: "/repo", number: 7)] = .init(
                events: [
                    ReviewComment(
                        id: 17,
                        author: "coderabbitai[bot]",
                        body: "<details><summary>Outside diff comments (1)</summary>\n\n"
                            + "**file.swift:1**: Fix this.\n\n</details>",
                        kind: "COMMENTED",
                        authorType: "Bot",
                    ),
                ],
            )
        }
        let host = NSHostingView(rootView: PullRequestFooterView(model: model))
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try model.reviewCount(for: #require(model.selected)) == 1)
        let countedWidth = host.fittingSize.width
        let finding = try #require(model.pullRequests
            .cachedConversation(repositoryPath: "/repo", number: 7)
            .reviewThreads
            .first)
        try model.pullRequests.setOutsideDiffResolved(finding, resolved: true, repositoryPath: "/repo", number: 7)
        UtilityTabTarget.resolutionMarksChanged()
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try model.reviewCount(for: #require(model.selected)) == 0)
        #expect(host.fittingSize.width < countedWidth)
    }
}
