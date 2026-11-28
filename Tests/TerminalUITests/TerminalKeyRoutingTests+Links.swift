import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

extension TerminalKeyRoutingTests {
    @Test(arguments: [NSEvent.ModifierFlags(), .command])
    func `clicking an agent link opens its hidden destination`(modifiers: NSEvent.ModifierFlags) throws {
        let pane = try Self.focusedPane(herdrBacked: true)
        defer { pane.window.close() }
        let address = "https://example.org/docs"
        pane.view.feed(text: "\u{1B}[?2026h\u{1B}[4m\u{1B}]8;;" + address
            + "\u{1B}\\Read the guide\u{1B}[0m\u{1B}]8;;\u{1B}\\\u{1B}[?2026l")
        try TerminalMouse.select(in: pane.view, row: 0, from: 2, to: 8)
        #expect(pane.view.getSelection() == "ad the")
        #expect(pane.capture.links.isEmpty)
        try TerminalMouse.select(in: pane.view, row: 0, from: 9, to: 9, modifiers: modifiers)
        #expect(pane.capture.links == [address])
    }

    @Test
    func `an underlined file label looks up the transcript only on a click`() throws {
        let pane = try Self.focusedPane(herdrBacked: true)
        defer { pane.window.close() }
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        pane.view.terminalDelegate = coordinator
        var opened = [AgentOutputLink]()
        pane.view.agentOutputLink = Binding(get: { nil }, set: { link in
            if let link {
                opened.append(link)
            }
        })
        let label = "four poses side by side"
        pane.view.feed(text: "Here are the \u{1B}[34;4m" + label + "\u{1B}[0m.")
        try TerminalMouse.select(in: pane.view, row: 0, from: 14, to: 18)
        try TerminalMouse.select(in: pane.view, row: 0, from: 3, to: 3)
        try TerminalMouse.select(in: pane.view, row: 0, from: 16.95, to: 17.05)
        #expect(opened.isEmpty)
        let onePoint = 1 / PaneTerminalView.cellSize(of: pane.view).width
        try TerminalMouse.select(in: pane.view, row: 0, from: 17.25, to: 17.25 + onePoint)
        #expect(opened == [.label(label, externalBrowser: false)])
        let file = try #require(URL(string: "file:///worktree/poses.jpg"))
        pane.view.feed(text: "\r\n\u{1B}[4m\u{1B}]8;;" + file.absoluteString + "\u{7}poses\u{1B}]8;;\u{7}\u{1B}[0m")
        try TerminalMouse.select(in: pane.view, row: 1, from: 2, to: 2)
        #expect(opened == [.label(label, externalBrowser: false), .destination(file)])
    }

    @Test
    func `a link split across terminal rows keeps its whole label`() throws {
        let pane = try Self.focusedPane(herdrBacked: true)
        defer { pane.window.close() }
        let label = "four poses side by side"
        let prefix = String(repeating: " ", count: pane.view.terminalDimensions.cols - 5)
        pane.view.feed(text: prefix + "\u{1B}[4m" + label + "\u{1B}[0m")
        let cell = PaneTerminalView.cellSize(of: pane.view)
        let point = NSPoint(x: cell.width * 2, y: pane.view.bounds.height - cell.height * 1.5)
        #expect(pane.view.underlinedLabel(at: point) == label)
    }

    @Test
    func `opening a terminal web link reveals the Browser tab`() throws {
        let defaults = UserDefaults.standard
        let keys = [
            UtilityTabTarget.addressKey, UtilityTabTarget.requestKey, UtilityTabTarget.key,
            UtilityTabTarget.visibilityKey,
        ]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(false, forKey: UtilityTabTarget.visibilityKey)
        let pane = try Self.focusedPane(herdrBacked: true)
        defer { pane.window.close() }
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        pane.view.terminalDelegate = coordinator
        let address = "https://example.org/help"
        pane.view.feed(text: "\u{1B}]8;;" + address + "\u{7}Help\u{1B}]8;;\u{7}")
        try TerminalMouse.select(in: pane.view, row: 0, from: 1, to: 1)
        #expect(defaults.string(forKey: UtilityTabTarget.addressKey) == address)
        #expect(defaults.string(forKey: UtilityTabTarget.key) == UtilityTabTarget.browser)
        #expect(defaults.bool(forKey: UtilityTabTarget.visibilityKey))
    }
}
