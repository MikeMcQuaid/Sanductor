import Foundation

/// Reusable text with an optional repository schedule and launch history.
public struct SavedPrompt: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(name: String = "", prompt: String = "") {
        self.name = name
        self.prompt = prompt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        repositoryPath = try container.decodeIfPresent(String.self, forKey: .repositoryPath) ?? ""
        agent = try container.decodeIfPresent(AgentKind.self, forKey: .agent) ?? .claudeCode
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        effort = try container.decodeIfPresent(String.self, forKey: .effort) ?? ""
        schedule = try container.decodeIfPresent(PromptSchedule.self, forKey: .schedule)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        nextRun = try container.decodeIfPresent(Date.self, forKey: .nextRun)
        lastRun = try container.decodeIfPresent(Date.self, forKey: .lastRun)
        lastSession = try container.decodeIfPresent(String.self, forKey: .lastSession)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    // MARK: Public

    public var id: UUID = .init()
    public var name = ""
    public var prompt = ""
    public var repositoryPath = ""
    public var agent: AgentKind = .claudeCode
    public var model = ""
    public var effort = ""
    public var schedule: PromptSchedule?
    public var isEnabled = true
    public var nextRun: Date?
    public var lastRun: Date?
    public var lastSession: String?
    public var lastError: String?

    public var isValid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (schedule == nil || repositoryPath.isEmpty == false)
    }

    /// Stable across a launch retry, distinct across schedules and occurrences.
    public func branch(for date: Date) -> String {
        "scheduled_" + SessionName.slug(String(name.prefix(Self.nameLimit))) + "_"
            + date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + "_"
            + String(Int(date.timeIntervalSince1970)) + "_" + id.uuidString.prefix(Self.idLength).lowercased()
    }

    // MARK: Private

    private static let nameLimit = 40
    private static let idLength = 8
}
