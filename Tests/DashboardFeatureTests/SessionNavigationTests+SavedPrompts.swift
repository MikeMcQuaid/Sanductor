import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["", "CI failures\nKeep é, 🧑🏽‍💻 and `code`\n"], [false, true])
    func `saved prompts precede live text and focus the editor`(existing: String, marked: Bool) async throws {
        let input = AgentSessionForm.PromptTextView()
        var bound = "stale binding"
        let host = NSHostingView(rootView: AgentSessionForm.PromptEditor(
            text: Binding(get: { bound }, set: { bound = $0 }), view: input,
        ))
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(textViews(in: host).first)
        if marked {
            editor.setMarkedText(
                existing,
                selectedRange: NSRange(location: existing.utf16.count, length: 0),
                replacementRange: NSRange(location: 0, length: editor.string.utf16.count),
            )
        } else {
            editor.string = existing
        }
        bound = "stale binding"
        let saved = "Look at the last commit and fix these CI failures:"
        let expected = saved + (existing.isEmpty ? "" : "\n\n" + existing)
        #expect(input.prepend(saved) == expected)
        #expect(input.capture() == expected)
        #expect(bound == expected)
        #expect(window.firstResponder === editor)
    }
}
