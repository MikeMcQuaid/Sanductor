import Foundation

/// The host's current sidebar classification and optional manual blocker.
public struct SidebarEntry: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        target: SidebarTarget,
        status: SidebarStatus,
        activity: AgentActivity?,
        block: WorkBlock?,
        pullRequest: SidebarPullRequest? = nil,
        lastEventAt: Date? = nil,
        // swiftlint:disable:next discouraged_optional_boolean - Older projections lack this Git reading.
        hasUnpushedCommits: Bool? = nil,
        paneID: String? = nil,
        transcriptPath: String? = nil,
    ) {
        self.lastEventAt = lastEventAt
        self.hasUnpushedCommits = hasUnpushedCommits
        self.paneID = paneID
        self.transcriptPath = transcriptPath
        self.target = target
        legacyStatus = status == .needsPush ? (activity == .done ? .done : .worktree) : status
        workflowStatus = status == .needsPush ? status.rawValue : nil
        self.activity = activity
        self.block = block
        self.pullRequest = pullRequest
    }

    // MARK: Public

    // swiftlint:disable:next discouraged_optional_boolean - Older projections lack this Git reading.
    public let hasUnpushedCommits: Bool?
    public let lastEventAt: Date?
    public let paneID: String?
    public let transcriptPath: String?
    public let target: SidebarTarget
    public let activity: AgentActivity?
    public let block: WorkBlock?
    public let pullRequest: SidebarPullRequest?

    public var status: SidebarStatus {
        workflowStatus.flatMap(SidebarStatus.init(rawValue:)) ?? legacyStatus
    }

    // MARK: Private

    // SwiftFormat strips raw values that match the coding key.
    // swiftlint:disable explicit_enum_raw_value
    private enum CodingKeys: String, CodingKey {
        case target
        case paneID
        case transcriptPath
        case hasUnpushedCommits
        case lastEventAt
        case activity
        case block
        case pullRequest
        case workflowStatus
        case legacyStatus = "status"
    }

    // swiftlint:enable explicit_enum_raw_value

    // Older phones decode every entry as a closed enum and reject an entire sidebar with an unfamiliar case.
    private let legacyStatus: SidebarStatus
    private let workflowStatus: String?
}
