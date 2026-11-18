/// The host's current sidebar classification and optional manual blocker.
public struct SidebarEntry: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        target: SidebarTarget,
        status: SidebarStatus,
        activity: AgentActivity?,
        block: WorkBlock?,
        pullRequest: SidebarPullRequest? = nil,
    ) {
        self.target = target
        self.status = status
        self.activity = activity
        self.block = block
        self.pullRequest = pullRequest
    }

    // MARK: Public

    public let target: SidebarTarget
    public let status: SidebarStatus
    public let activity: AgentActivity?
    public let block: WorkBlock?
    public let pullRequest: SidebarPullRequest?
}
