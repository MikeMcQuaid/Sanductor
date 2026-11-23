import AppKit
@testable import TerminalUI
import Testing

/// Clipboard copies contain readable text rather than terminal cells.
@MainActor
struct TerminalCopyTests {
    @Test(arguments: [false, true])
    func `failed preparation preserves clipboard ownership and contents`(clearing: Bool) async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("previous", forType: .string)
        board.setString("<b>previous</b>", forType: .html)
        let clipboard = ClipboardCopy(to: board, clearing: clearing)
        let generation = board.changeCount
        #expect(await clipboard.writeText { throw CocoaError(.fileWriteNoPermission) } == false)
        #expect(board.changeCount == generation)
        #expect(board.string(forType: .string) == (clearing ? nil : "previous"))
        #expect(board.string(forType: .html) == (clearing ? nil : "<b>previous</b>"))
    }

    @Test
    func `overlapping copies honour the latest request even when the older text is ready first`() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let first = ClipboardCopy(to: board)
        let second = ClipboardCopy(to: board)
        #expect(await first.writeText { "older" } == false)
        #expect(await second.writeText { "newer" })
        #expect(board.string(forType: .string) == "newer")
    }

    @Test
    func `agent terminal drops and pastes prefer file URLs and keep original image bytes`() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let view = PaneTerminalView(frame: .zero)
        let file = URL(fileURLWithPath: "/a file.png")
        let bytes = Data([1, 2, 3])
        board.setString("plain text", forType: .string)
        view.onAttach = { _ in Issue.record("Text was treated as an attachment"); return false }
        #expect(view.attach(from: board) == false)
        board.setData(bytes, forType: .png)
        view.onAttach = { attachments in
            guard case let .image(data, name) = attachments.first else {
                return false
            }

            return data == bytes && name == "image.png"
        }
        #expect(view.attach(from: board))
        board.setString(file.absoluteString, forType: .fileURL)
        view.onAttach = { attachments in
            guard case let .file(url) = attachments.first else {
                return false
            }

            return url == file
        }
        #expect(view.attach(from: board))
    }

    @Test(arguments: [false, true])
    func `selection copies clean cursor gaps and padding`(multiline: Bool) throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.feed(text: "\u{1B}[31m▎ Hello\u{1B}[10Gworld\u{1B}[0m")
        if multiline {
            view.feed(text: "\r\n▎ wrapped text")
        }
        try TerminalMouse.select(in: view, row: 0, from: 0, to: 30, endRow: multiline ? 1 : 0)
        view.copy(NSMenuItem())
        #expect(
            view.copyPasteboard.string(forType: .string) == (multiline ? "Hello  world wrapped text" : "Hello  world"),
        )
    }

    @Test
    func `rectangular copies clean hidden characters without reflowing`() {
        let view = PaneTerminalView(frame: .zero)
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.selectedBlockText = "First\u{0}line  \n  Second\u{07}\u{202E} line\u{202C}  "
        view.copy(NSMenuItem())
        #expect(view.copyPasteboard.string(forType: .string) == "First line\n  Second line")
    }

    @Test
    func `copy last reply offers formatted text beside its Markdown`() async {
        let view = PaneTerminalView(frame: .zero)
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.onCopyReply = { "Use **bold** and `code`." }
        await view.copyOutput(lastReply: true)?.value
        #expect(view.copyPasteboard.string(forType: .string) == "Use **bold** and `code`.")
        #expect(view.copyPasteboard.string(forType: .html)?.contains("<strong>bold</strong>") == true)
        #expect(view.menu(for: NSEvent())?.items.map(\.title).contains("Copy Last Reply") == true)
    }

    @Test(arguments: [false, true])
    func `a terminal copy preserves anything newer copied during the read`(allOutput: Bool) async {
        let view = PaneTerminalView(frame: .zero)
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        let read = {
            // A selection is copied while the reply is being read.
            view.copyPasteboard.clearContents()
            view.copyPasteboard.setString("newer", forType: .string)
            return "older reply"
        }
        if allOutput {
            view.onCopyAllOutput = read
        } else {
            view.onCopyReply = read
        }
        await view.copyOutput(lastReply: allOutput == false)?.value
        #expect(view.copyPasteboard.string(forType: .string) == "newer")
    }

    @Test
    func `the items a pane adds to its menu are enabled`() {
        let view = PaneTerminalView(frame: .zero)
        view.onCopyReply = { nil }
        view.onCopyAllOutput = { nil }
        view.onReattach = { /* Only the item's presence matters. */ }
        let added = view.menu(for: NSEvent())?
            .items
            .filter { ["Copy Last Reply", "Copy All Output", "Reattach"].contains($0.title) } ?? []
        #expect(added.count == 3)
        #expect(added.allSatisfy { view.validateUserInterfaceItem($0) })
    }

    @Test
    func `copy all output uses the same cleanup`() async {
        let view = PaneTerminalView(frame: .zero)
        view.reflowsCopies = true
        view.copyPasteboard = .withUniqueName()
        defer { view.copyPasteboard.releaseGlobally() }
        view.onCopyAllOutput = {
            "\u{0}▎ Hello\u{0}world\u{07}\u{2066}  \r\n  wrapped text\u{2069}  "
        }
        await view.copyOutput(lastReply: false)?.value
        #expect(view.copyPasteboard.string(forType: .string) == "Hello world wrapped text")
    }
}
