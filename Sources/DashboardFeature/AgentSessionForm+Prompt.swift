import AppKit
import SanductorData
import SanductorInterface
import SwiftUI
import TerminalUI

extension AgentSessionForm {
    static let spacing: CGFloat = 10
    static let promptHeight: CGFloat = 140
    static let contextHeight: CGFloat = 70

    struct PromptEditor: NSViewRepresentable {
        @Binding var text: String

        let view: PromptTextView
        var service: SessionService?
        var style: InterfaceStyle = .init()

        func makeNSView(context _: Context) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            view.isRichText = false
            view.allowsUndo = true
            view.isVerticallyResizable = true
            view.autoresizingMask = .width
            unsafe view.textContainer?.widthTracksTextView = true
            scroll.documentView = view
            return scroll
        }

        func updateNSView(_: NSScrollView, context: Context) {
            view.draft = $text
            view.service = service
            view.font = style.appKitFont(.body)
            view.isEditable = context.environment.isEnabled && view.isStaging == false
            // The draft can arrive older than the typing it mirrors;
            // the editor being typed in owns its text.
            if view.string != text, view.hasMarkedText() == false, unsafe view.window?.firstResponder !== view {
                view.string = text
            }
        }
    }

    final class PromptTextView: NSTextView, ObservableObject {
        // MARK: Lifecycle

        deinit {
            // The form owns its editor.
        }

        // MARK: Internal

        override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
            AttachmentPasteboard.types + super.readablePasteboardTypes
        }

        override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
            AttachmentPasteboard.types + super.acceptableDragTypes
        }

        @Published private(set) var isStaging = false
        var draft: Binding<String>?
        var service: SessionService?

        override func readSelection(from board: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
            guard AttachmentPasteboard.types.contains(type), let service else {
                return super.readSelection(from: board, type: type)
            }

            let attachments = AttachmentPasteboard.attachments(from: board, type: type)
            guard isEditable, isStaging == false, attachments.isEmpty == false else {
                return false
            }

            let selection = selectedRange()
            let original = string
            isStaging = true
            isEditable = false
            Task.detached { [weak self] in
                var paths = [String]()
                do {
                    for attachment in attachments {
                        try paths.append(service.stageDroppedFile(attachment))
                    }
                } catch {
                    await ErrorLog.shared.report("Could not attach the dropped item: " + error.localizedDescription)
                }
                await self?.finishStaging(paths, in: original, at: selection)
            }
            return true
        }

        override func didChangeText() {
            super.didChangeText()
            draft?.wrappedValue = string
        }

        func prepend(_ prefix: String) -> String? {
            guard let existing = capture() else {
                return nil
            }

            _ = unsafe window?.makeFirstResponder(self)
            insertText(
                prefix + (existing.isEmpty ? "" : "\n\n" + existing),
                replacementRange: NSRange(location: 0, length: string.utf16.count),
            )
            return string
        }

        /// Replaces the text and the draft together, even while the
        /// editor has focus, which the draft alone never overrides.
        func replace(with text: String) {
            unmarkText()
            string = text
            draft?.wrappedValue = text
        }

        func capture() -> String? {
            guard isEditable, let root = unsafe window?.contentView else {
                return nil
            }

            let point = root.convert(NSPoint(x: visibleRect.midX, y: visibleRect.midY), from: self)
            guard root.hitTest(point)?.isDescendant(of: self) == true else {
                return nil
            }

            // Ending composition can restore the binding's older value.
            let text = string
            unmarkText()
            return text
        }

        // MARK: Private

        private func finishStaging(_ paths: [String], in original: String, at selection: NSRange) {
            isStaging = false
            isEditable = true
            guard paths.isEmpty == false, unsafe window != nil, string == original, draft?.wrappedValue == original
            else {
                return
            }

            insertText(paths.joined(separator: " ") + " ", replacementRange: selection)
        }
    }
}
