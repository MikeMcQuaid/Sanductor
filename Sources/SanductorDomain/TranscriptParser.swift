import Foundation

/// Decodes transcript lines from a local file or an SSH stream.
public enum TranscriptParser {
    // MARK: Public

    /// Parses further whole lines onto a log already read, so a
    /// transcript still being written is followed without rereading
    /// what came before.
    public static func append(_ lines: String, to results: inout [TranscriptEntry]) {
        let decoder = Self.makeDecoder()
        for line in lines.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: data)
            else {
                continue
            }

            if let payload = parsed.payload {
                appendCodexEntry(payload, to: &results)
                continue
            }
            guard let role = role(of: parsed.type), parsed.isMachinery == false else {
                continue
            }

            for item in parsed.message?.content?.items ?? [] {
                let id = (results.last?.id ?? -1) + 1
                if let text = item.text, text.isEmpty == false {
                    results.append(TranscriptEntry(id: id, role: role, text: text))
                } else if item.type == "tool_use", let name = item.name {
                    let detail = item.input?.summary
                    let text = detail.map { name + ": " + $0 } ?? name
                    results.append(TranscriptEntry(id: id, role: .tool, text: text))
                }
            }
        }
    }

    // MARK: Package

    package static func title(in head: String) -> String {
        let decoder = Self.makeDecoder()
        for line in head.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let parsed = try? decoder.decode(TranscriptLine.self, from: lineData),
                  parsed.type == "user", parsed.isMachinery == false,
                  let text = parsed.message?.content?.items.compactMap(\.text).first
            else {
                continue
            }

            let flattened = text.replacing("\n", with: " ")
            return String(flattened.prefix(Self.titleCharacterLimit))
        }
        return ""
    }

    // MARK: Private

    private struct TranscriptLine: Decodable {
        let type: String?
        let message: TranscriptMessage?
        let payload: CodexPayload?
        // Absent from the JSON on ordinary lines.
        // swiftlint:disable:next discouraged_optional_boolean
        let isMeta: Bool?
        // Absent from the JSON on ordinary lines.
        // swiftlint:disable:next discouraged_optional_boolean
        let isCompactSummary: Bool?
        let promptSource: String?

        /// Whether a Claude Code line is its own bookkeeping rather
        /// than conversation. Skill preambles and command caveats
        /// are marked meta and a compaction summary says what it is.
        /// A user line nobody typed (a command echo, a task
        /// notification) names the system as its source or, naming
        /// none, opens with one of the tags that wrap such lines.
        /// Any other leading tag is a prompt about markup.
        var isMachinery: Bool {
            if isMeta == true || isCompactSummary == true {
                return true
            }
            guard type == "user" else {
                return false
            }

            let text = message?.content?.items.first?.text ?? ""
            return promptSource.map { $0 == "system" }
                ?? ["<command-name>", "<local-command-"].contains(where: text.hasPrefix)
        }
    }

    private struct TranscriptMessage: Decodable {
        let content: TranscriptBlocks?
    }

    /// A message's blocks. Claude Code stores a typed prompt as
    /// plain text where every other message is a list, so the text
    /// reads as one text block.
    private struct TranscriptBlocks: Decodable {
        // MARK: Lifecycle

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                items = [TranscriptContent(type: "text", name: nil, text: text, input: nil)]
            } else {
                items = try container.decode([TranscriptContent].self)
            }
        }

        // MARK: Internal

        let items: [TranscriptContent]
    }

    private struct TranscriptContent: Decodable {
        let type: String?
        let name: String?
        let text: String?
        let input: ToolInput?
    }

    /// The interesting fields of a tool invocation's input, whichever
    /// the tool populates. Snake case keys like `file_path` arrive via
    /// the decoder's key strategy.
    private struct ToolInput: Decodable {
        // MARK: Internal

        let command: String?
        let filePath: String?
        let path: String?
        let pattern: String?
        let description: String?
        let prompt: String?
        let url: String?

        /// The most displayable single field, truncated.
        var summary: String? {
            let value = command ?? filePath ?? path ?? pattern ?? url ?? description ?? prompt
            return value.map { String($0.replacing("\n", with: " ").prefix(Self.summaryLimit)) }
        }

        // MARK: Private

        private static let summaryLimit = 200
    }

    private static let titleCharacterLimit = 100

    /// The one decoder configuration: transcript JSON uses snake case
    /// keys in tool inputs.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func role(of type: String?) -> TranscriptEntry.Role? {
        switch type {
        case "user":
            .user

        case "assistant":
            .assistant

        default:
            nil
        }
    }
}
