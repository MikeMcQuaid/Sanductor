@testable import PRFeature
import SanductorData
import SanductorDomain
import Synchronization
import Testing

/// Merging from the bottom of a stack. Split from the stack tests
/// for length.
extension PullRequestStackTests {
    @Test(arguments: ["MERGED", "CLOSED", "OPEN"])
    func `refresh follows the next layer only when the displayed pull request merges`(state: String) async {
        let fixtures = PullRequestsModelTests()
        let item = fixtures.item(branch: "feature", ahead: 0)
        let model = fixtures.makeModel(items: [item], worktreePath: item.worktree.path)
        let branches = ["feature", "z-middle", "a-top"]
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: branches, checkedOut: "feature"))
        }
        model.fetchList = { _, _ in [fixtures.summary(1, head: "feature")] }
        await model.reload()
        model.fetchList = { scope, _ in
            if scope == .branch("feature") {
                return [fixtures.summary(1, head: "feature", state: state)]
            }
            return [fixtures.summary(2, head: "z-middle")]
        }
        await model.reload(keepingSelection: true)
        #expect(model.listedBranch == (state == "MERGED" ? "z-middle" : "feature"))
    }

    @Test(arguments: [false, true])
    func `repository listings follow only an unambiguous child of the merged PR`(ambiguous: Bool) {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel()
        model.scope = .open
        let lower = fixtures.summary(1, head: "lower")
        let upper = fixtures.summary(2, head: "upper", base: "lower")
        let other = fixtures.summary(3, head: "other", base: ambiguous ? "lower" : "main")
        model.summaries = [lower, upper, other]
        model.selected = lower
        model.cacheEnriched(fixtures.summary(1, head: "lower", state: "MERGED"))
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path, scope: .open, summaries: [upper, other],
        )
        model.repaintFromCache()
        #expect(model.selected?.number == (ambiguous ? nil : upper.number))
    }

    @Test(arguments: [
        (GitHubClient.MergeResult.pending, "Requested the stack merge."),
        (.merged, "Merged the stack."),
        (.enqueued, "Queued the stack."),
    ])
    func `the bottom of a stack merges through the stack`(outcome: GitHubClient.MergeResult, status: String) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "lower" }
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "lower"))
        }
        await model.reload()
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("lower"),
            summaries: [fixtures.summary(1, head: "lower", base: "main")],
        )

        // Even the bottom entry must link the stack before merging.
        #expect(model.listedParent == nil)
        #expect(model.isInStack)
        #expect(model.canMergeStack)

        let done = Mutex([String]())
        model.performLinkStack = { _ in done.withLock { $0.append("link") } }
        model.performMergeStack = { _, number in
            done.withLock { $0.append("merge " + String(number)) }
            return outcome
        }
        model.selected = fixtures.summary(1, head: "lower", base: "main", mergeable: "MERGEABLE", checks: "SUCCESS")
        #expect(await model.performMergeAction())
        #expect(done.withLock { $0 } == ["link", "merge 1"])
        #expect(model.status == status)
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "lower"))
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "upper") == false)
    }
}
