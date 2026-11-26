@testable import DashboardFeature
import Foundation
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `a merged PR with unfinished stack branches keeps the row out of Merged`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        let item = try #require(model.groups.first?.items.first)
        let branch = item.worktree.branch
        model.store.update { metadata in
            metadata.pullRequestCache[fixture.repository.path + "#" + branch] = PullRequestSummary(
                number: 7,
                title: "Lower",
                url: "",
                headBranch: branch,
                mergeable: "",
                reviewDecision: "",
                checks: "",
                state: "MERGED",
                closedAt: Date(),
            )
        }
        #expect(model.keepUnfinishedStack(["upper"], for: item) == .unfinishedStack(["upper"]))
        #expect(model.unfinishedMergeBranches(for: item) == ["upper"])
        #expect(model.sidebarStatus(for: item) == .partiallyMerged)
        model.derivedStacks[item.worktree.path] = BranchStack(base: "trunk", branches: [branch], checkedOut: branch)
        #expect(model.unfinishedMergeBranches(for: item).isEmpty)
        #expect(model.sidebarStatus(for: item) == .merged)
    }

    @Test(arguments: [false, true])
    func `the sidebar uses GitHub positions and includes unpublished branches`(unpublished: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        if unpublished {
            fixture.model.derivedStacks[item.worktree.path] = BranchStack(
                base: "trunk", branches: ["bottom", "middle", "main", "upper", "unpushed"], checkedOut: "main",
            )
        }
        fixture.model.store.update { metadata in
            metadata.pullRequestCache[fixture.repository.path + "#main"] = PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "main",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                baseBranch: "middle",
                stackStanding: StackStanding(position: 3, height: 4, base: "middle"),
            )
        }
        #expect(fixture.model.stackStanding(for: item)
            == StackStanding(position: 3, height: unpublished ? 5 : 4, base: "middle"))
    }
}
