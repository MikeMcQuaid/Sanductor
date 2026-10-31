import AppKit
import SanductorData

/// Copies feedback with the same size and file-lifetime rules as autofix.
public enum PromptClipboard {
    /// Replaces oversized clipboard text with a reference to its complete file.
    @discardableResult
    public static func copy(
        _ text: String,
        to pasteboard: NSPasteboard = .general,
        prepare: (String) throws -> String = { text in
            guard text.utf8.count > PromptPayload.inlineByteLimit else {
                return text
            }

            let paths = WorkspacePaths.current()
            return try PromptPayload.prepare(text, paths: paths, store: MetadataStore(file: paths.metadataFile))
        },
    ) -> Bool {
        pasteboard.clearContents()
        do {
            return try pasteboard.setString(prepare(text), forType: .string)
        } catch {
            ErrorLog.shared.report("Could not prepare feedback for copying: " + error.localizedDescription)
            return false
        }
    }
}
