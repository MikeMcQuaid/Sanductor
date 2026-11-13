import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

extension SessionNavigationTests {
    @Test
    func `pasting a prefix then typing a suffix submits both immediately`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            AgentSessionForm.promptKey: "",
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
        let host = NSHostingView(rootView: form)
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(fixture.textView(in: host))
        window.makeFirstResponder(editor)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        clipboard.setString("BEGIN 0123456789 abcdefghijklmnopqrstuvwxyz ", forType: .string)
        #expect(editor.readSelection(from: clipboard))
        try await Task.sleep(for: .milliseconds(10))
        for (code, character) in [(UInt16(14), "E"), (45, "N"), (2, "D")] {
            try editor.keyDown(with: #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .shift,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: code,
            )))
        }
        let expected = "BEGIN 0123456789 abcdefghijklmnopqrstuvwxyz END"
        try #require(editor.string == expected)
        try fixture.submit(in: host, windowNumber: window.windowNumber)
        for _ in 0 ..< 50 where submitted == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(submitted?.prompt == expected)
    }
}
