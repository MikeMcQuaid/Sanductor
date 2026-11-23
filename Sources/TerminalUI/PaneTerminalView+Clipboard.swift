import AppKit
import SanductorDomain

/// Attachment and output transfers shared by terminal clipboard actions.
extension PaneTerminalView {
    func attach(from board: NSPasteboard) -> Bool {
        guard let onAttach else {
            return false
        }

        let attachments = AttachmentPasteboard.attachments(from: board)
        return attachments.isEmpty == false && onAttach(attachments)
    }

    /// The whole recent output from herdr, reflowed like a selection
    /// copy when this pane reflows, onto the clipboard.
    @objc
    func copyAllOutput(_: Any?) {
        copyOutput(lastReply: false)
    }

    /// The newest reply onto the clipboard, formatted and as Markdown.
    @objc
    func copyReply(_: Any?) {
        copyOutput(lastReply: true)
    }

    @discardableResult
    func copyOutput(lastReply: Bool) -> Task<Void, Never>? {
        guard let read = lastReply ? onCopyReply : onCopyAllOutput else {
            return nil
        }

        let clipboard = ClipboardCopy(to: copyPasteboard)
        return Task { [reflowsCopies] in
            if lastReply {
                await MarkdownClipboard.copy(to: clipboard, reading: read)
            } else if let text = await read() {
                await clipboard.writeText {
                    reflowsCopies ? PasteableText.reflow(text) : PasteableText.cleanTerminalCopy(text)
                }
            }
        }
    }
}
