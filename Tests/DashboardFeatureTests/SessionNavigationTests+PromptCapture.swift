import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

extension SessionNavigationTests {
    @Test(arguments: [false, true])
    func `prompt capture ignores stale bindings and the focused neighbouring editor`(marked: Bool) async throws {
        let input = AgentSessionForm.PromptEditorHost(rootView: AnyView(EmptyView()))
        let host = NSHostingView(rootView: HStack {
            AgentSessionForm.PromptEditor(text: .constant("Makes "), view: input)
            TextEditor(text: .constant("Another editor"))
        })
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editors = textViews(in: host)
        let prompt = try #require(editors.first { $0.string == "Makes " })
        let other = try #require(editors.first { $0.string == "Another editor" })
        window.makeFirstResponder(other)
        let replacement = NSRange(location: 0, length: prompt.string.utf16.count)
        if marked {
            prompt.setMarkedText(
                "The complete visible prompt",
                selectedRange: NSRange(location: 0, length: 0),
                replacementRange: replacement,
            )
        } else {
            // Simulate native text ahead of the binding without a change notification.
            prompt.string = "The complete visible prompt"
        }
        try #require(prompt.string == "The complete visible prompt")
        #expect(input.capture() == "The complete visible prompt")
        #expect(other.string == "Another editor")
    }

    @Test(arguments: [false, true])
    func `an unreadable prompt is neither submitted nor cleared`(coveredByEditor: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            AgentSessionForm.promptKey: "Keep this draft",
            "agentKind": "claude",
            "agentModel": "sonnet",
            "agentEffort": "high",
        ])
        defer { restore() }
        var submitted: AgentSessionForm.Submission?
        let form = AgentSessionForm(
            model: fixture.model,
            repository: fixture.repository,
            submitTitle: "Start agent",
            submitHelp: "Start",
        ) { submission in submitted = submission }
        let host = NSHostingView(rootView: form.overlay {
            if coveredByEditor {
                TextEditor(text: .constant("Another editor"))
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        })
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(textViews(in: host).first { $0.string == "Keep this draft" })
        editor.insertText(
            " and the latest edits",
            replacementRange: NSRange(location: editor.string.utf16.count, length: 0),
        )
        let expected = editor.string
        try fixture.submit(in: host, windowNumber: window.windowNumber)
        try await Task.sleep(for: .milliseconds(100))
        #expect(submitted == nil)
        #expect(editor.string == expected)
        #expect(UserDefaults.standard.string(forKey: AgentSessionForm.promptKey) == expected)
    }
}
