import AppKit
import SwiftUI

extension AgentSessionForm {
    static let promptHeight: CGFloat = 140
    static let contextHeight: CGFloat = 70

    /// Keeps the system TextEditor in its own host so submission can identify its native input.
    struct PromptEditor: NSViewRepresentable {
        @Binding var text: String

        let view: PromptEditorHost

        func makeNSView(context _: Context) -> PromptEditorHost {
            view.sizingOptions = []
            return view
        }

        func updateNSView(_ view: PromptEditorHost, context: Context) {
            view.rootView = AnyView(TextEditor(text: $text)
                .interfaceFont(.body)
                .disabled(context.environment.isEnabled == false))
        }
    }

    final class PromptEditorHost: NSHostingView<AnyView> {
        // MARK: Lifecycle

        deinit {
            // The form owns the editor's host.
        }

        // MARK: Internal

        func capture() -> String? {
            var editor = textView
            if editor == nil {
                layoutSubtreeIfNeeded()
                editor = textView
            }
            guard let editor else {
                return nil
            }

            // Ending composition can restore the binding's older value.
            let text = editor.string
            editor.unmarkText()
            return text
        }

        // MARK: Private

        private var textView: NSTextView? {
            guard let editor = textView(in: self), editor.isEditable,
                  let root = unsafe window?.contentView
            else {
                return nil
            }

            let point = root.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
            guard root.hitTest(point)?.isDescendant(of: editor) == true else {
                return nil
            }

            return editor
        }

        private func textView(in view: NSView) -> NSTextView? {
            (view as? NSTextView) ?? view.subviews.lazy.compactMap { self.textView(in: $0) }.first
        }
    }
}
