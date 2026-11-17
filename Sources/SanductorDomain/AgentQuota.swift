import Foundation

/// One account allowance reported by an agent's usage service.
public struct AgentQuota: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    /// Creates a quota window; absent allowances are omitted by the adapter.
    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date?,
        modelName: String? = nil,
        availableResets: Int? = nil,
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.modelName = modelName
        self.availableResets = availableResets
    }

    // MARK: Public

    /// The provider's stable window identifier.
    public let id: String
    /// The period this allowance covers.
    public let label: String
    /// A separate model allowance; nil for the account's overall usage.
    public let modelName: String?
    /// Percentage consumed, which can exceed the allowance.
    public let usedPercent: Double
    /// The provider's reset time, when reported.
    public let resetsAt: Date?
    /// Manual resets available for this allowance; nil when the provider does not report them.
    public let availableResets: Int?
}
