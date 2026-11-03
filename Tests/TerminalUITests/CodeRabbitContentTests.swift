import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct CodeRabbitContentTests {
    @Test(arguments: [
        "### Review receipt findings\n\n- Keep this finding.",
        "- Require CODEOWNERS to request review\n  - Keep the nested finding.",
        "- [ ] Require tests before we run review\n  - Keep the nested finding.",
        "Thanks for using CodeRabbit to detect this bug. Keep this finding.",
        "<p>Thanks for using CodeRabbit to detect this bug. Keep this finding.</p>",
        "<details><summary>Share state safely</summary>Keep this finding.</details>",
        "> Validate usage-based billing before saving. Keep this finding.",
        "<blockquote><p>Validate usage-based billing before saving. Keep this finding.</p></blockquote>",
        "<blockquote><p>Keep this finding.</p><p>This review was completed with usage-based billing.</p></blockquote>",
    ])
    func `findings resembling bot notices remain intact`(_ source: String) {
        #expect(ReviewCommentText(source, author: "coderabbitai").text == source)
    }

    @Test
    func `status titles escape markup while retaining their visible text`() throws {
        let title = "Check `</summary><details>` & `<value>`"
        let source = "> [!IMPORTANT]\n> ## " + title + "\n>\n> Keep this explanation."
        let chunks = MarkdownText.parsedChunks(ReviewCommentText(source, author: "coderabbitai").text)
        #expect(chunks.count == 1)
        let notice = try #require(chunks.first)
        #expect(String(MarkdownText.content(notice.detailsSummary ?? "").characters)
            == "Important: Check </summary><details> & <value>")
        #expect(String(MarkdownText.content(notice.text).characters).contains("Keep this explanation."))
        #expect(MarkdownText.parsedChunks(notice.text).allSatisfy { $0.detailsSummary == nil })
    }

    @Test(arguments: ["\"", "'", ""], ["&", "&amp;", "&#38;"])
    func `finding links retain bullets across attribute source spellings`(quote: String, ampersand: String) {
        let url = "https://example.com/?a=1" + ampersand + "b=2#discussion_r1"
        let source = "<p><a href=" + quote + url + quote
            + "><img alt='Major'>Check metadata.</a></p>"
        let content = MarkdownText.content(ReviewCommentText(source, author: "coderabbitai").text)
        #expect(MarkdownTestSupport.kinds(content).contains(.unorderedList))
        #expect(String(content.characters).contains("Major ›Check metadata."))
        #expect(content.runs.contains { $0.link?.absoluteString == "https://example.com/?a=1&b=2#discussion_r1" })
    }

    @Test
    func `raw preformatted examples keep their headings unchanged`() {
        let example = "<pre>\n# configuration\n## details\n</pre>"
        let source = "## Findings\n\n" + example
        let shown = ReviewCommentText(source, author: "coderabbitai").text
        #expect(shown == "### Findings\n\n" + example)
        #expect(String(MarkdownText.content(shown).characters).contains("# configuration\n## details"))
    }
}
