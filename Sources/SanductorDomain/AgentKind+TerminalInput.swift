public extension AgentKind {
    /// Claude opens its questions directly; Codex queues them behind Shift-Left.
    var answerQuestionInput: [UInt8] {
        switch self {
        case .codexCLI:
            Array("\u{1B}[1;2D".utf8)

        case .claudeCode:
            []
        }
    }

    /// The default binding for queueing a draft while the agent is working.
    var queueInput: [UInt8] {
        switch self {
        case .codexCLI:
            Array("\t".utf8)

        case .claudeCode:
            Array("\r".utf8)
        }
    }

    /// Claude's Ctrl-X Ctrl-S works without negotiating extended keyboard modes.
    var sendInputNow: [UInt8] {
        switch self {
        case .codexCLI:
            Array("\r".utf8)

        case .claudeCode:
            Array("\u{18}\u{13}".utf8)
        }
    }
}
