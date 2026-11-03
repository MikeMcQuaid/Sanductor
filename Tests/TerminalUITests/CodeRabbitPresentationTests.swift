import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct CodeRabbitPresentationTests {
    @Test(arguments: [("IMPORTANT", "Review skipped"), ("WARNING", "Review limit reached"), ("note", "Review delayed")])
    func `status callouts collapse with their nested details and no retry clutter`(kind: String, title: String) throws {
        let source = """
        > [!\(kind)]
        > ## \(title)
        >
        > Keep the reason and [usage](https://example.com/usage).
        >
        > ```html
        > <strong>Keep this code.</strong>
        > ```
        >
        > <details><summary>Run configuration</summary>
        >
        > - **Profile**: CHILL
        >
        > </details>
        >
        > You can disable this status message by setting the `reviews.review_status` to `false` \
        in the CodeRabbit configuration file.
        >
        > Use the checkbox below for a quick retry:
        > - [ ] <!-- {"checkboxId":"retry"} --> Trigger review

        Keep the finding after the notice.
        """
        let shown = ReviewCommentText(source, author: "coderabbitai").text
        let chunks = MarkdownText.parsedChunks(shown)
        let notice = try #require(chunks.first)
        #expect(notice.detailsSummary == kind.capitalized + ": " + title)
        #expect(notice.text.contains("Keep the reason"))
        #expect(notice.text.contains("<strong>Keep this code.</strong>"))
        #expect(MarkdownText.parsedChunks(notice.text).contains { $0.detailsSummary == "Run configuration" })
        #expect(chunks.last?.text.contains("Keep the finding after") == true)
        #expect(shown.contains("[!") == false)
        #expect(shown.contains("reviews.review_status") == false)
        #expect(shown.contains("quick retry") == false)
        #expect(shown.contains("Trigger review") == false)
        #expect(ReviewCommentText(source, author: "human").text == source)
        let example = "```markdown\n" + source + "\n```"
        #expect(ReviewCommentText(example, author: "coderabbitai").text == example)
    }

    @Test(arguments: ["Usage-based review receipt", "USAGE-BASED Review Receipt", "Review receipt"])
    func `receipts and billing notes share a collapsed disclosure`(title: String) throws {
        let source = """
        ### \(title)

        - Mode: Continue automatically
        - Reviewed files: 4
        - Charged: $1.00
        - [View usage details](https://example.com/billing?tab=usage&orgId=one)

        > [!NOTE]
        > This review was completed with usage-based billing: more context.

        ## Findings

        Keep this finding.
        """
        let shown = ReviewCommentText(source, author: "coderabbitai").text
        let chunks = MarkdownText.parsedChunks(shown)
        let receipt = try #require(chunks.first)
        #expect(receipt.detailsSummary == "Usage-based review receipt")
        #expect(receipt.text.contains("Charged: $1.00"))
        #expect(receipt.text.contains("usage-based billing"))
        #expect(receipt.text.contains("orgId=one"))
        #expect(chunks.last?.text.contains("Keep this finding.") == true)
        #expect(chunks.last?.text.contains("### Findings") == true)
        #expect(MarkdownTestSupport.kinds(MarkdownText.content(receipt.text)).contains(.unorderedList))
        #expect(ReviewCommentText(source, author: "copilot").text == source)
        let example = "```markdown\n" + source + "\n```"
        #expect(ReviewCommentText(example, author: "coderabbitai").text == example)
    }

    @Test
    func `a quoted disclosure does not leave an empty alert above it`() {
        let source = """
        > [!NOTE]
        > <details><summary>Summarized by CodeRabbit Free</summary>
        >
        > Keep this explanation.
        >
        > </details>
        """
        let shown = ReviewCommentText(source, author: "coderabbitai").text
        let chunks = MarkdownText.parsedChunks(shown)
        #expect(chunks.count == 1)
        #expect(chunks.first?.detailsSummary == "Summarized by CodeRabbit Free")
        #expect(chunks.first?.text.contains("Keep this explanation.") == true)
    }

    @Test(arguments: ["Major", "minor", "Advisory"])
    func `finding badges become bullets and separators without altering inline severity`(severity: String) {
        let source = """
        ## Findings

        <p><a href="https://example.com/#discussion_r1"><picture><img alt="\(severity)" src="badge.svg"></picture> \
        Check metadata.</a></p>
        <p><a href="https://example.com/#discussion_r2"><picture><img alt="Minor" src="minor.svg"></picture> \
        Check fallback.</a></p>

        **<picture><img alt="" src="minor.svg"></picture> Minor** · **Correctness**
        """
        let shown = ReviewCommentText(source, author: "coderabbitai").text
        let content = MarkdownText.content(shown)
        #expect(MarkdownTestSupport.kinds(content).contains(.header(level: 3)))
        #expect(MarkdownTestSupport.kinds(content).contains(.listItem(ordinal: 2)))
        #expect(String(content.characters).contains(severity + " › Check metadata."))
        #expect(String(content.characters).contains("Minor › Check fallback."))
        #expect(String(content.characters).contains("Minor · Correctness"))
        #expect(ReviewCommentText(source, author: "human").text == source)
    }
}
