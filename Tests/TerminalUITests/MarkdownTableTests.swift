import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownTableTests {
    @Test
    func `HTML tables retain rows cells and inline formatting`() {
        let source = """
        <table><caption>Results</caption><thead><tr><th>File</th><th>Status</th></tr></thead>
        <tbody><tr><td><code>a|b</code></td><td><strong>Ready</strong></td></tr></tbody></table>
        """
        let content = MarkdownText.content(source)
        let kinds = MarkdownTestSupport.kinds(content)
        #expect(kinds.contains(.tableHeaderRow))
        #expect(kinds.contains(.tableRow(rowIndex: 1)))
        #expect(String(content.characters) == "ResultsFileStatusa|bReady")
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        #expect(content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test
    func `a table without headers keeps every data row`() {
        let content = MarkdownText.content("<table><tr><td>one</td></tr><tr><td>two</td><td>three</td></tr></table>")
        let kinds = MarkdownTestSupport.kinds(content)
        #expect(kinds.contains(.tableRow(rowIndex: 1)))
        #expect(kinds.contains(.tableRow(rowIndex: 2)))
        #expect(String(content.characters).contains("one"))
        #expect(String(content.characters).contains("twothree"))
    }
}
