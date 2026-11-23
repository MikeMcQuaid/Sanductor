import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

extension SessionNavigationTests {
    @Test
    func `the prompt stages dropped files and raw images at the selection`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([AgentSessionForm.promptKey: "Check this"])
        defer { restore() }
        let host = NSHostingView(rootView: AgentSessionForm(
            model: fixture.model, repository: fixture.repository, submitTitle: "Start", submitHelp: "Start",
        ) { _ in Issue.record("Dropping an attachment submitted the prompt") })
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(fixture.textView(in: host))
        let file = URL(fileURLWithPath: fixture.root + "/build log.txt")
        let bytes = Data("diagnostics".utf8)
        try bytes.write(to: file)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.writeObjects([file, file.appendingPathExtension("missing")].map { url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }))
        editor.setSelectedRange(NSRange(location: 6, length: 4))
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "Check this")
        #expect(editor.isEditable == false)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let fileDeadline = ContinuousClock.now + .seconds(5)
        while editor.isEditable == false, ContinuousClock.now < fileDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let path = String(editor.string.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        try #require(path.hasPrefix(fixture.root + "/shared/tmp/drop-"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == bytes)
        board.clearContents()
        board.setData(bytes, forType: .png)
        editor.selectAll(nil)
        #expect(editor.readSelection(from: board))
        let imageDeadline = ContinuousClock.now + .seconds(5)
        while editor.string.hasSuffix(".png ") == false, ContinuousClock.now < imageDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let image = editor.string.trimmingCharacters(in: .whitespaces)
        #expect(image.hasSuffix(".png"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: image)) == bytes)
    }

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
