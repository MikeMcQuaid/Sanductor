import Foundation

/// A short line submitted to the selected agent from Reader.
public struct ReaderReply: Sendable {
    // MARK: Lifecycle

    public init?(_ text: String) {
        guard Self.accepts(text), text.trimmingCharacters(in: .whitespaces).isEmpty == false else {
            return nil
        }

        self.text = text
    }

    // MARK: Public

    public static func accepts(_ text: String) -> Bool {
        text.utf8.count <= maximumBytes && text.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    }

    public static func wasSubmitted(_ output: String, to paneID: String) -> Bool {
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let result = envelope["result"] as? [String: Any], result["type"] as? String == "agent_prompted",
              let agent = result["agent"] as? [String: Any]
        else {
            return false
        }

        return agent["pane_id"] as? String == paneID
    }

    public func arguments(paneID: String) -> [String] {
        ["agent", "prompt", paneID, text]
    }

    // MARK: Private

    private static let maximumBytes = 1_000

    private let text: String
}
