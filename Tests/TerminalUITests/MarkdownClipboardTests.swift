import AppKit
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownClipboardTests {
    @Test
    func `code keeps its own face and nothing written reads as markup`() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reply = """
        Edit `Sources/App.swift` as sandvault-<you>, then `Set<String>` & run:

        ```swift
        let names: Set<String> = []
        ```
        """
        MarkdownClipboard.copy(reply, to: pasteboard)
        let html = pasteboard.string(forType: .html) ?? ""
        #expect(html.contains("monospace\">Sources/App.swift</code>"))
        #expect(html.contains("sandvault-&lt;you&gt;"))
        #expect(html.contains("monospace\">Set&lt;String&gt;</code> &amp; run:"))
        #expect(html.contains("monospace\"><code>let names: Set&lt;String&gt; = []\n</code></pre>"))
        #expect(pasteboard.string(forType: .string) == reply)
    }

    @Test
    func `link and image attributes cannot close their quotes`() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        MarkdownClipboard.copy(
            #"![plot](plot.png '"><b>extra</b>') and [docs](https://example.com/?a=1&b="2")"#, to: pasteboard,
        )
        let html = pasteboard.string(forType: .html) ?? ""
        #expect(html.contains("<b>") == false)
        #expect(html.contains(#"title="&quot;&gt;&lt;b&gt;extra&lt;/b&gt;""#))
        #expect(html.contains(#"href="https://example.com/?a=1&amp;b=&quot;2&quot;""#))
        #expect(html.contains(#"src="plot.png""#))
    }
}
