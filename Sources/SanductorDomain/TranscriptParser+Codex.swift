/// Reading Codex's rollouts, split from the reader for length.
extension TranscriptParser {
    /// Whether user-role text is Codex's own injected context rather
    /// than something the user typed.
    package static func isInjectedCodexContext(_ text: String) -> Bool {
        text.hasPrefix("# AGENTS.md instructions")
            || text.hasPrefix("<user_instructions>")
            || text.hasPrefix("<environment_context>")
    }

    /// The Codex rollout format wraps everything in typed payloads.
    /// Current rollouts use `message` payloads with a role and a
    /// content array plus `custom_tool_call`; the flat
    /// `user_message`, `agent_message` and `function_call` shapes
    /// are older rollouts, kept readable.
    struct CodexPayload: Decodable {
        // Absent from the JSON when a payload carries no content.
        // swiftlint:disable:next discouraged_optional_collection
        let content: [CodexContent]?
        let type: String?
        let role: String?
        let message: String?
        let name: String?
        let arguments: String?
        let input: String?
    }

    struct CodexContent: Decodable {
        let text: String?
    }

    /// Maps one Codex payload onto a log entry: user and assistant
    /// messages read as prose, tool calls as tool lines. Developer
    /// messages and Codex's injected instruction preambles are
    /// machinery, not conversation, and stay hidden. The flat
    /// `user_message`, `agent_message` and `function_call` shapes
    /// are older rollouts, kept readable.
    /// Rollouts often record one utterance twice: as a flat event
    /// payload and again as a typed response item. Adjacent repeats
    /// of the same role and text collapse to one entry.
    static func appendCodexEntry(_ payload: CodexPayload, to results: inout [TranscriptEntry]) {
        let id = (results.last?.id ?? -1) + 1
        let entry: TranscriptEntry? =
            switch payload.type {
            case "message":
                codexMessage(payload, id: id)

            case "custom_tool_call":
                codexToolLine(
                    name: payload.name,
                    detail: payload.input?.split(separator: "\n").first.map(String.init),
                    id: id,
                )

            case "user_message":
                codexProse(payload.message, role: .user, id: id)

            case "agent_message":
                codexProse(payload.message, role: .assistant, id: id)

            case "function_call":
                codexToolLine(name: payload.name, detail: payload.arguments, id: id)

            default:
                nil
            }
        if let entry, results.last.map({ $0.role == entry.role && $0.text == entry.text }) != true {
            results.append(entry)
        }
    }

    private static func codexMessage(_ payload: CodexPayload, id: Int) -> TranscriptEntry? {
        let role: TranscriptEntry.Role? =
            switch payload.role {
            case "user":
                .user

            case "assistant":
                .assistant

            default:
                nil
            }
        let text = (payload.content ?? []).compactMap(\.text).joined(separator: "\n")
        guard let role, text.isEmpty == false, Self.isInjectedCodexContext(text) == false else {
            return nil
        }

        return TranscriptEntry(id: id, role: role, text: text)
    }

    private static func codexProse(_ message: String?, role: TranscriptEntry.Role, id: Int) -> TranscriptEntry? {
        guard let message, message.isEmpty == false else {
            return nil
        }

        return TranscriptEntry(id: id, role: role, text: message)
    }

    private static func codexToolLine(name: String?, detail: String?, id: Int) -> TranscriptEntry? {
        guard let name else {
            return nil
        }

        let suffix = detail.flatMap { $0.isEmpty ? nil : ": " + $0 } ?? ""
        return TranscriptEntry(id: id, role: .tool, text: name + suffix)
    }
}
