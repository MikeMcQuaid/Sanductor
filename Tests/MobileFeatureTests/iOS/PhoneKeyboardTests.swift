#if os(iOS)
    @testable import MobileFeature
    import SanductorDomain
    import SwiftTerm
    import Testing
    import UIKit

    struct PhoneKeyboardTests {
        // MARK: Internal

        @Test(arguments: AgentKind.allCases)
        func `queue ignores latched modifiers and sends only once`(agent: AgentKind) throws {
            let terminal = PhoneTerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            terminal.agent = agent
            let capture = InputCapture()
            terminal.terminalDelegate = capture
            let keyboard = PhoneKeyboard(terminal: terminal, expanded: true)
            terminal.controlModifier = true
            terminal.shiftModifier = true
            let queue = try #require(buttons(in: keyboard).first { $0.accessibilityLabel == "Queue" })
            queue.sendActions(for: .touchDown)
            queue.sendActions(for: .primaryActionTriggered)
            #expect(capture.bytes == agent.queueInput)
            #expect(terminal.controlModifier == false)
            #expect(terminal.shiftModifier == false)
        }

        @Test
        func `accessory offers keyboard dismissal without disabling terminal input`() {
            let terminal = PhoneTerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            let keyboard = PhoneKeyboard(terminal: terminal)
            let keys = buttons(in: keyboard)
            #expect(keys.contains { $0.accessibilityLabel == "Hide keyboard" })
            #expect(keys.count == 7)
            #expect(terminal.canBecomeFirstResponder)
        }

        @Test
        func `clear line sends editing keys without interrupting the agent`() throws {
            let terminal = PhoneTerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            let capture = InputCapture()
            terminal.terminalDelegate = capture
            let keyboard = PhoneKeyboard(terminal: terminal, expanded: true)
            let clear = try #require(buttons(in: keyboard).first { $0.accessibilityLabel == "Clear line" })
            clear.sendActions(for: .primaryActionTriggered)
            #expect(capture.bytes == [1, 11])
        }

        @Test(arguments: [false, true])
        func `keyboard reserves its height before UIKit presents it`(expanded: Bool) {
            let terminal = PhoneTerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            let keyboard = PhoneKeyboard(terminal: terminal, expanded: expanded)
            #expect(keyboard.frame.height == keyboard.intrinsicContentSize.height)
            #expect(keyboard.frame.height > 0)
        }

        // MARK: Private

        private final class InputCapture: TerminalViewDelegate {
            // MARK: Lifecycle

            deinit { /* No resources beyond the captured input. */ }

            // MARK: Internal

            var bytes: [UInt8] = []

            func send(source _: TerminalView, data: ArraySlice<UInt8>) {
                bytes.append(contentsOf: data)
            }

            func requestOpenLink(source _: TerminalView, link _: String, params _: [String: String]) {
                // Input only.
            }

            func sizeChanged(source _: TerminalView, newCols _: Int, newRows _: Int) { /* Input only. */ }
            func setTerminalTitle(source _: TerminalView, title _: String) { /* Input only. */ }
            func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) { /* Input only. */ }
            func scrolled(source _: TerminalView, position _: Double) { /* Input only. */ }
            func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) { /* Input only. */ }
        }

        private func buttons(in keyboard: PhoneKeyboard) -> [UIButton] {
            keyboard.subviews.compactMap { $0 as? UIStackView }.flatMap { rows in
                rows.arrangedSubviews.flatMap { $0.subviews.compactMap { $0 as? UIButton } }
            }
        }
    }
#endif
