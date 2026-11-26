import AppKit
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownClipboardTests {
    @Test
    func `code keeps its own face and nothing written reads as markup`() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reply = """
        Edit `Sources/App.swift` as sandvault-<you>, then `Set<String>` & run:

        ```swift
        let names: Set<String> = []
        ```
        """
        await MarkdownClipboard.copy(to: ClipboardCopy(to: pasteboard)) { reply }
        let html = pasteboard.string(forType: .html) ?? ""
        #expect(html.contains("monospace\">Sources/App.swift</code>"))
        #expect(html.contains("sandvault-&lt;you&gt;"))
        #expect(html.contains("monospace\">Set&lt;String&gt;</code> &amp; run:"))
        #expect(html.contains("monospace\"><code>let names: Set&lt;String&gt; = []\n</code></pre>"))
        #expect(pasteboard.string(forType: .string) == reply)
    }

    @Test
    func `a rich text paste keeps bold and both kinds of code`() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        await MarkdownClipboard.copy(to: ClipboardCopy(to: board)) {
            "**bold** and `inline`\n\n```\n    indented\nsecond line\n```"
        }
        let data = try #require(board.data(forType: .rtf))
        let copied = unsafe try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let traits: [String: NSFontDescriptor.SymbolicTraits] = [
            "bold": .bold, "inline": .monoSpace, "indented": .monoSpace,
        ]
        for (word, trait) in traits {
            let range = try #require(copied.string.range(of: word))
            let offset = NSRange(range, in: copied.string).location
            let font = unsafe try #require(copied.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
            #expect(font.fontDescriptor.symbolicTraits.contains(trait))
        }
        #expect(copied.string.contains("    indented\nsecond line"))
    }

    @Test(arguments: [
        "| Key | Value |\n| --- | --- |\n| one | **two** |",
        "<table><tr><th>Key</th><th>Value</th></tr><tr><td>one</td><td><b>two</b></td></tr></table>",
    ])
    func `a copied reply offers a table with formatted cells`(source: String) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        await MarkdownClipboard.copy(to: ClipboardCopy(to: board)) { source }
        let html = try #require(board.string(forType: .html))
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Key</th>"))
        #expect(html.contains("<td><strong>two</strong></td>"))
        #expect(board.string(forType: .string) == source)
    }

    @Test
    func `link and image attributes cannot close their quotes`() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        await MarkdownClipboard.copy(to: ClipboardCopy(to: pasteboard)) {
            #"![plot](plot.png '"><b>extra</b>') and [docs](https://example.com/?a=1&b="2")"#
        }
        let html = pasteboard.string(forType: .html) ?? ""
        #expect(html.contains("<b>") == false)
        #expect(html.contains(#"title="&quot;&gt;&lt;b&gt;extra&lt;/b&gt;""#))
        #expect(html.contains(#"href="https://example.com/?a=1&amp;b=&quot;2&quot;""#))
        #expect(html.contains(#"src="plot.png""#))
    }
}
