import Foundation

// MARK: - SidebarStatus

/// Shared sidebar groups, in their display priority.
public enum SidebarStatus: String, CaseIterable, Codable, Sendable {
    case launchFailed = "Launch failed"
    case needsInput = "Needs input"
    case needsPush = "Needs push"
    case ciFailing = "CI failing"
    case changesRequested = "Changes requested"
    case unaddressedComments = "Unaddressed comments"
    case readyToMerge = "Ready to merge"
    case working = "Working"
    case waitingForCI = "Waiting for CI"
    case waitingForReview = "Waiting for review"
    case queued = "Queued"
    case done = "Done"
    case draft = "Draft"
    case open = "Open"
    case merged = "Merged"
    case closed = "Closed"
    case idleAgent = "Idle agents"
    case worktree = "Worktree"
    case branch = "Branch"
    case exited = "Exited"
    case hostDirectory = "On your Mac"
    case blocked = "Blocked"
    case defaultBranch = "Default branch"

    // MARK: Public

    /// Linked worktrees stay distinct even when they hold the default branch.
    public static func inactiveStatus(for target: SidebarTarget, defaultBranch: String?) -> Self {
        if target.path != target.repositoryPath {
            return .worktree
        }
        return target.branch == defaultBranch ? .defaultBranch : .branch
    }

    /// Keeps the row's existing agent-versus-PR event precedence.
    public static func status(
        session: AgentSession?,
        pullRequest: PullRequestSummary?,
        inactiveStatus: Self = .branch,
        isHostDirectory: Bool = false,
        launchFailed: Bool = false,
        blocked: Bool = false,
        reviewThreadsKnown: Bool = false,
        hasUnpushedCommits: Bool = false,
        pendingPushAt: Date? = nil,
    ) -> Self {
        if isHostDirectory {
            return .hostDirectory
        }
        if launchFailed {
            return .launchFailed
        }
        if blocked {
            return .blocked
        }
        let next: Self =
            if let session, session.precedes(pullRequest, pendingPushAt: pendingPushAt) {
                agentStatus(session, inactiveStatus: inactiveStatus)
            } else if let pullRequest {
                pullRequestStatus(pullRequest, reviewThreadsKnown: reviewThreadsKnown)
            } else {
                pendingPushAt == nil ? inactiveStatus : .waitingForCI
            }
        return hasUnpushedCommits && next != .working && next != .needsInput ? .needsPush : next
    }

    // MARK: Private

    private static func agentStatus(_ session: AgentSession, inactiveStatus: Self) -> Self {
        guard session.status == .running else {
            return .exited
        }

        return switch session.sidebarActivity {
        case .blocked:
            .needsInput

        case .working:
            .working

        case .done:
            .done

        case .idle,
             nil:
            session.agent == nil ? inactiveStatus : .idleAgent
        }
    }

    private static func pullRequestStatus(_ pullRequest: PullRequestSummary, reviewThreadsKnown: Bool) -> Self {
        switch pullRequest.state {
        case "MERGED":
            return .merged

        case "CLOSED":
            return .closed

        default:
            break
        }
        if pullRequest.pendingPushAt != nil {
            return .waitingForCI
        }
        if pullRequest.isQueued {
            return .queued
        }
        if pullRequest.isDraft {
            return .draft
        }
        if pullRequest.hasFailingChecks {
            return .ciFailing
        }
        if pullRequest.reviewDecision == "CHANGES_REQUESTED" {
            return .changesRequested
        }
        if pullRequest.unresolvedComments > 0 {
            return .unaddressedComments
        }
        return reviewStatus(pullRequest, reviewThreadsKnown: reviewThreadsKnown)
    }

    private static func reviewStatus(_ pullRequest: PullRequestSummary, reviewThreadsKnown: Bool) -> Self {
        if pullRequest.checks == "PENDING" {
            return .waitingForCI
        }
        if pullRequest.reviewDecision == "REVIEW_REQUIRED" || pullRequest.awaitsCopilotReview
            || pullRequest.requestedReviewers.isEmpty == false
        {
            return .waitingForReview
        }
        if reviewThreadsKnown, pullRequest.checks == "SUCCESS", pullRequest.reviewDecision == "APPROVED",
           pullRequest.mergeable == "MERGEABLE"
        {
            return .readyToMerge
        }
        return .open
    }
}

// MARK: - SidebarMode

/// The two sidebar presentations, remembered separately on each device.
public enum SidebarMode: String, CaseIterable, Sendable {
    case repository = "Repository"
    case status = "Status"
}
