import Foundation

/// The PR facts shared with the phone, without its conversation or credentials.
public struct SidebarPullRequest: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(_ summary: PullRequestSummary) {
        number = summary.number
        url = summary.url
        details = Details(summary)
    }

    // MARK: Public

    /// Read-only PR facts shared independently of repository visibility.
    public struct Details: Codable, Equatable, Sendable {
        // MARK: Lifecycle

        init(_ summary: PullRequestSummary) {
            state = summary.state
            isDraft = summary.isDraft
            isQueued = summary.isQueued
            checks = summary.checks
            checksDescription = summary.checksDescription
            reviewDecision = summary.reviewDecision
            mergeable = summary.state == "OPEN" && summary.mergeable == "CONFLICTING" ? summary.mergeable : nil
        }

        // MARK: Public

        public let state: String
        public let isDraft: Bool
        public let isQueued: Bool
        public let checks: String
        public let checksDescription: String
        public let reviewDecision: String
        /// Only conflicts on open PRs need a badge; absent in older snapshots.
        public let mergeable: String?

        public var stateLabel: String {
            if isQueued {
                return "Queued"
            }
            switch state {
            case "MERGED":
                return "Merged"

            case "CLOSED":
                return "Closed"

            default:
                return isDraft ? "Draft" : "Open"
            }
        }
    }

    public let number: Int
    /// Older snapshots can contain only the PR link.
    public let details: Details?

    /// Shared snapshots are writable by agents; only GitHub HTTPS PR links may open.
    public var webURL: URL? {
        guard let components = URLComponents(string: url),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil
        else {
            return nil
        }

        let path = components.path.split(separator: "/")
        guard path.count == Self.pathComponentCount,
              path.dropFirst(Self.repositoryComponentCount) == ["pull", Substring(String(number))], number > 0
        else {
            return nil
        }

        return components.url
    }

    // MARK: Private

    private static let pathComponentCount = 4
    private static let repositoryComponentCount = 2

    private let url: String
}
