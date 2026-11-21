import Foundation
import SanductorDomain
import Testing

struct SidebarEventTests {
    @Test(arguments: ["OPEN", "MERGED", "CLOSED"], [AgentActivity.blocked, .working, .done, .idle])
    func `the newer event wins regardless of state priority`(state: String, activity: AgentActivity) {
        let now = Date()
        let session = AgentSession(
            name: "agent", agent: .codexCLI, status: .running, activity: activity, lastActivityAt: now,
        )
        var pullRequest = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            stateChangedAt: now.addingTimeInterval(1),
        )
        #expect(session.precedes(pullRequest) == false)
        pullRequest.stateChangedAt = now.addingTimeInterval(-1)
        #expect(session.precedes(pullRequest))
    }

    @Test(arguments: [AgentActivity.blocked, .working, .done, .idle, nil])
    func `equal or missing event times use the previous priority`(activity: AgentActivity?) {
        let now = Date()
        let session = AgentSession(
            name: "agent", agent: .codexCLI, status: .running, activity: activity, lastActivityAt: now,
        )
        var pullRequest = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            stateChangedAt: now,
        )
        let active = activity.map { [.blocked, .working, .done].contains($0) } ?? false
        #expect(session.precedes(pullRequest) == active)
        pullRequest.stateChangedAt = nil
        #expect(session.precedes(pullRequest) == active)
        #expect(session.precedes(nil))
    }

    @Test
    func `a completed turn yields to the push then CI and a requested human review`() {
        let now = Date()
        let done = AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: .done, lastActivityAt: now)
        let pull = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "SUCCESS",
            updatedAt: now.addingTimeInterval(1),
            requestedReviewers: ["reviewer"],
        )
        #expect(SidebarStatus.status(session: done, pullRequest: pull, hasUnpushedCommits: true) == .needsPush)
        #expect(SidebarStatus.status(session: done, pullRequest: pull.awaitingChecks()) == .waitingForCI)
        #expect(SidebarStatus.status(session: done, pullRequest: pull) == .waitingForReview)
        let undated = AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: .done)
        #expect(SidebarStatus.status(session: undated, pullRequest: pull) == .waitingForReview)
    }

    @Test
    func `unpublished work needs a first push and a confirmed push supersedes the old git counts`() {
        let tree = Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "work", path: "/tree")
        let first = WorktreeItem(worktree: tree, session: nil, isDirty: false, aheadOfUpstream: nil, aheadOfDefault: 2)
        #expect(first.needsPush(hasPullRequest: false, lastPush: nil))
        let tracked = WorktreeItem(worktree: tree, session: nil, isDirty: false, aheadOfUpstream: 1)
        let previous = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "CHANGES_REQUESTED",
            checks: "FAILURE",
            unresolvedComments: 1,
        )
        #expect(tracked.needsPush(hasPullRequest: true, lastPush: previous.pendingPushAt))
        let pushed = previous.awaitingChecks()
        #expect(tracked.needsPush(hasPullRequest: true, lastPush: pushed.pendingPushAt) == false)
        #expect(SidebarStatus.status(session: nil, pullRequest: pushed) == .waitingForCI)
    }

    @Test
    func `a check completing after an agent turn supplies the next action`() {
        let now = Date()
        let done = AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: .done, lastActivityAt: now)
        let check = PullRequestCheck(
            name: "CI",
            status: "COMPLETED",
            conclusion: "FAILURE",
            requirement: .required,
            completedAt: now.addingTimeInterval(1),
        )
        let pull = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            stateChangedAt: now.addingTimeInterval(-1),
            checkDetails: [check],
        )
        #expect(SidebarStatus.status(session: done, pullRequest: pull) == .ciFailing)
    }

    @Test
    func `closing time and event times survive edits pushes and caching`() throws {
        let now = Date()
        let merged = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: "MERGED",
            closedAt: now,
        )
        #expect(merged.stateChangedAt == now)
        let edited = merged.retitled("Title", body: "Body").awaitingChecks()
        let decoded = try JSONDecoder().decode(PullRequestSummary.self, from: JSONEncoder().encode(edited))
        #expect(decoded.stateChangedAt == now)
    }
}
