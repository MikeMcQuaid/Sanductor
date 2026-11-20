// MARK: - TranscriptSession

/// A past agent conversation discovered from its transcript file,
/// whoever created it.
public struct TranscriptSession: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a record of a discovered transcript; `resumeID`
    /// defaults to the id for agents whose file name is the resume
    /// handle.
    public init(id: String, path: String, agent: AgentKind, modifiedAt: Int, title: String, resumeID: String? = nil) {
        self.id = id
        self.path = path
        self.agent = agent
        self.modifiedAt = modifiedAt
        self.title = title
        self.resumeID = resumeID ?? id
    }

    // MARK: Public

    /// The transcript's file name stem. Unique per file, unlike
    /// Codex's embedded session id, which subagent rollouts share
    /// with their parent thread.
    public let id: String

    /// What the agent's resume flag takes: the file name stem for
    /// per-directory transcripts, Codex's embedded session id.
    public let resumeID: String

    /// The transcript file's absolute path.
    public let path: String

    /// The agent that owns the transcript.
    public let agent: AgentKind

    /// When the transcript was last written, in seconds since 1970;
    /// an `Int` keeps this type free of Foundation.
    public let modifiedAt: Int

    /// The first user prompt, trimmed for display.
    public let title: String
}

// MARK: - TranscriptEntry

/// One displayable step of a conversation log.
public struct TranscriptEntry: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a log entry.
    public init(id: Int, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    // MARK: Public

    /// Who produced the entry.
    public enum Role: Hashable, Sendable {
        /// The human's prompt.
        case user
        /// The agent's reply text.
        case assistant
        /// A tool invocation, summarised by name.
        case tool
    }

    /// The entry's position in the transcript.
    public let id: Int

    /// Who produced the entry.
    public let role: Role

    /// The displayable text.
    public let text: String
}

public extension [TranscriptEntry] {
    /// The newest reply's Markdown: the last unbroken run of the
    /// agent's prose, since a reply's text blocks arrive as separate
    /// entries. A tool call ends the run as a prompt does: what the
    /// agent said on its way to an answer is not the answer. Nil
    /// before the agent has written any.
    var lastReply: String? {
        guard let end = lastIndex(where: { $0.role == .assistant }) else {
            return nil
        }

        let start = self[..<end].lastIndex { $0.role != .assistant }.map { $0 + 1 } ?? startIndex
        return self[start ... end].map(\.text).joined(separator: "\n\n")
    }
}
