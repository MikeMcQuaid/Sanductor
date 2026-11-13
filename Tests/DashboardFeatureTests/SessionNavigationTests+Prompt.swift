import AppKit
@testable import DashboardFeature
import SwiftUI
import TerminalUI
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["typed", "pasted", "marked"], [false, true])
    func `command return submits every edit before the next render`(input: String, settledFocus: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            AgentSessionForm.promptKey: "Makes ",
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
        let host = NSHostingView(rootView: AnyView(form))
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(fixture.textView(in: host))
        window.makeFirstResponder(editor)
        if settledFocus {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(window.firstResponder === editor)
        let expected = "Make Fixes #1234 in the PR view rendering link the #1234 to the relevant issue/PR URL"
            + " so I can click on it and open it like other links in the application."
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        if input == "marked" {
            editor.setMarkedText(
                expected,
                selectedRange: NSRange(location: expected.utf16.count, length: 0),
                replacementRange: editor.selectedRange(),
            )
        } else {
            for edit in input == "pasted" ? [expected] : expected.map(String.init) {
                editor.insertText(edit, replacementRange: editor.selectedRange())
            }
        }
        #expect(editor.string == expected)
        try fixture.submit(in: host, windowNumber: window.windowNumber)
        for _ in 0 ..< 50 where submitted == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(submitted?.prompt == expected)
    }

    @Test(arguments: [false, true])
    func `a covered form cannot steal Cmd Return or submit an older draft`(pasted: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            AgentSessionForm.promptKey: "First",
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
        var coveredSubmission: AgentSessionForm.Submission?
        let covered = AgentSessionForm(
            model: fixture.model,
            repository: fixture.repository,
            submitTitle: "Start agent",
            submitHelp: "Start",
        ) { submission in coveredSubmission = submission }
        let host = NSHostingView(rootView: AnyView(covered.hidden(true).overlay { form }))
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(textViews(in: host).first { candidate in
            let point = host.convert(NSPoint(x: candidate.bounds.midX, y: candidate.bounds.midY), from: candidate)
            return host.hitTest(point)?.isDescendant(of: candidate) == true
        })
        window.makeFirstResponder(editor)
        let text = "\nKeep é, 👩🏽‍💻, `backticks`, $HOME and every final word."
        let edits = pasted ? [String(repeating: text, count: 1_000)] : text.map(String.init)
        for edit in edits {
            editor.insertText(edit, replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            try await Task.sleep(for: .milliseconds(10))
        }
        editor.insertText(" final words", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        let expected = "First" + edits.joined() + " final words"
        #expect(editor.string == expected)
        try fixture.submit(in: host, windowNumber: window.windowNumber)
        for _ in 0 ..< 50 where submitted == nil && coveredSubmission == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coveredSubmission == nil)
        #expect(submitted?.prompt == expected)
    }

    func textViews(in view: NSView) -> [NSTextView] {
        if let editor = view as? NSTextView {
            return [editor]
        }
        return view.subviews.flatMap { textViews(in: $0) }
    }
}
