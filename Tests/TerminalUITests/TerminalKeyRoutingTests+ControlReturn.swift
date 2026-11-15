import AppKit
@testable import TerminalUI
import Testing

extension TerminalKeyRoutingTests {
    @Test(arguments: [("\r", UInt16(36)), ("\u{3}", 76)], [false, true])
    func `agent control return reaches the terminal before AppKit opens a context menu`(
        key: (character: String, code: UInt16),
        enhanced: Bool,
    ) throws {
        let pane = try Self.focusedPane(herdrBacked: true)
        defer { pane.window.close() }
        if enhanced {
            pane.view.feed(text: "\u{1B}[>1u")
        }
        pane.view.feed(text: "selected text")
        pane.view.selectAll(nil)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: pane.window.windowNumber,
            context: nil,
            characters: key.character,
            charactersIgnoringModifiers: key.character,
            isARepeat: false,
            keyCode: key.code,
        ))
        #expect(pane.view.routeKey(event) == nil)
        #expect(pane.capture.bytes == Array("\u{1B}[13;5u".utf8))
        #expect(pane.view.selectionActive == false)
    }

    @Test(arguments: [
        ((false, true), NSEvent.ModifierFlags.control),
        ((true, false), .control),
        ((true, true), []),
        ((true, true), [.control, .shift]),
        ((true, true), [.control, .option]),
        ((true, true), [.control, .command]),
    ] as [((Bool, Bool), NSEvent.ModifierFlags)])
    func `return keeps normal routing outside the focused agent shortcut`(
        state: (herdrBacked: Bool, focused: Bool),
        modifiers: NSEvent.ModifierFlags,
    ) throws {
        let pane = try Self.focusedPane(herdrBacked: state.herdrBacked)
        defer { pane.window.close() }
        if state.focused == false {
            try #require(pane.window.makeFirstResponder(nil))
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: pane.window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36,
        ))
        #expect(pane.view.routeKey(event) === event)
        #expect(pane.capture.bytes.isEmpty)
    }
}
