@testable import SanductorData
import SanductorDomain
import Testing

struct CodeRabbitOutsideDiffTests {
    // MARK: Internal

    @Test
    func `finding identity follows content across reviews and source revisions`() throws {
        let body = """
        <details><summary><img alt="Outside diff"> Check origins</summary><blockquote>

        **Check origins.** Keep this finding.

        [Open the source location](https://github.com/o/r/blob/old/file.swift#L42)

        <!-- cr-comment:v1:old -->

        </blockquote></details>
        """
        let first = try #require(CodeRabbitOutsideDiff.threads(in: [review(body)]).first)
        let repeated = try #require(CodeRabbitOutsideDiff.threads(in: [
            review(
                body.replacing("old", with: "new").replacing("Open the source location", with: "VIEW SOURCE CODE"),
                id: 8,
            ),
        ])
        .first)
        let changed = try #require(CodeRabbitOutsideDiff.threads(in: [
            review(body.replacing("Keep this finding.", with: "Different finding."), id: 8),
        ])
        .first)
        #expect(first.id == repeated.id)
        #expect(first.outsideDiffReviewID != repeated.outsideDiffReviewID)
        #expect(first.id != changed.id)
    }

    @Test(arguments: ["Outside diff", "OUTSIDE THE DIFF"])
    func `badge findings retain source anchors nested suggestions and stable identities`(badge: String) throws {
        let body = """
        ## Follow-up Comments
        <details><summary><sub><picture><img alt="\(badge)" src="badge.svg"></picture></sub> Check origins</summary>
        <blockquote>

        `169-175`: **Major** · **Functional Correctness**

        **Check origins.**

        <details><summary>Suggested fix</summary><dl><dd>

        ```diff
        + return value < limit && valid
        ```

        </dd></dl></details>

        [Open the source location](https://github.com/Homebrew/brew/blob/abcdef/Library/Homebrew/cargo.rb#L169-L175)

        </blockquote></details>
        <details><summary><img alt="Nitpick"> Unrelated nitpick</summary><blockquote>Ignore this.</blockquote></details>
        <details><summary>Review info</summary>Ignore metadata.</details>
        """
        let threads = CodeRabbitOutsideDiff.threads(in: [review(body)])
        let thread = try #require(threads.first)
        #expect(threads.count == 1)
        #expect(thread.path == "Library/Homebrew/cargo.rb")
        #expect(thread.line == 169)
        #expect(thread.outsideDiffReviewID == 7)
        #expect(thread.resolveID.isEmpty)
        #expect(thread.isResolved == false)
        #expect(thread.comments.first?.body.contains("Suggested fix") == true)
        #expect(ReviewCopy.text(thread).contains("+ return value < limit && valid"))
        #expect(ReviewCopy.text(thread).contains("Ignore") == false)
        #expect(CodeRabbitOutsideDiff.threads(in: [review(body)]) == threads)
    }

    @Test(arguments: ["Outside diff range comments", "outside-diff findings"])
    func `grouped findings preserve multiple files and ignore anchors inside code`(title: String) {
        let body = """
        <details><summary>⚠️ \(title) (3)</summary><blockquote>
        <details><summary>src/config.py (2)</summary><blockquote>

        `42-45`: **Validate config.**

        <details><summary>Suggested fix</summary>

        ```text
        `99`: This is code, not a finding.
        <details><summary>src/fake.py (1)</summary>Fake</details>
        ```

        </details>

        ---

        `100`: **Handle missing values.**

        </blockquote></details>
        <details><summary>src/utils.py (1)</summary><blockquote>

        `20`: **Handle errors.**

        </blockquote></details>
        </blockquote></details>
        <details><summary>🧹 Nitpick comments (1)</summary>

        **src/other.py:5**: Unrelated.

        </details>
        """
        let threads = CodeRabbitOutsideDiff.threads(in: [review(body)])
        #expect(threads.map(\.path) == ["src/config.py", "src/config.py", "src/utils.py"])
        #expect(threads.map(\.line) == [42, 100, 20])
        #expect(Set(threads.map(\.id)).count == 3)
        #expect(threads.contains { $0.resolveID.isEmpty == false } == false)
        #expect(threads.first?.comments.first?.body.contains("`99`: This is code") == true)
    }

    @Test
    func `direct anchors survive numbered suggestions and mixed file disclosures`() {
        let body = """
        <details><summary>⚠️ Outside diff range comments (3)</summary><blockquote>

        **src/config.py:42**: Validate config.

        <details><summary>Suggested fixes (1)</summary>

        Keep the default value.
        `42`: This is a suggested step, not another file.

        </details>
        <details><summary>src/utils.py (1)</summary><blockquote>

        `20`: **Handle errors.**

        </blockquote></details>

        **src/config.py:60**: Validate overrides too.

        </blockquote></details>
        """
        let threads = CodeRabbitOutsideDiff.threads(in: [review(body)])
        #expect(threads.count == 3)
        #expect(Set(threads.map(\.path)) == ["src/config.py", "src/utils.py"])
        #expect(Set(threads.compactMap(\.line)) == [20, 42, 60])
        let config = threads.first { $0.line == 42 }
        #expect(config?.comments.first?.body.contains("Keep the default value.") == true)
        #expect(config?.comments.first?.body.contains("This is a suggested step") == true)
        #expect(config?.comments.first?.body.contains("Handle errors.") == false)
        let direct = body.replacing(
            "<details><summary>src/utils.py (1)</summary><blockquote>\n\n"
                + "`20`: **Handle errors.**\n\n</blockquote></details>",
            with: "",
        )
        #expect(CodeRabbitOutsideDiff.threads(in: [review(direct)]).map(\.line) == [42, 60])
    }

    @Test
    func `only the latest submitted CodeRabbit review contributes findings`() {
        let body = """
        <details><summary>⚠️ Outside diff range comments (1)</summary>

        **src/config.py:42-45**: Validate config.

        </details>
        """
        let older = review(body)
        let latest = review("No findings.", id: 8)
        let comment = review(body, id: 9, kind: "")
        let spoof = review(body, id: 10, authorType: "User")
        #expect(CodeRabbitOutsideDiff.threads(in: [comment, spoof, older]).count == 1)
        #expect(CodeRabbitOutsideDiff.threads(in: [latest, comment, older]).isEmpty)
        #expect(CodeRabbitOutsideDiff.threads(in: [spoof, comment]).isEmpty)
    }

    @Test
    func `malformed locations and literal disclosures do not invent findings`() {
        let body = """
        ```html
        <details><summary>⚠️ Outside diff range comments (1)</summary>
        **fake.py:1**: Literal example.
        </details>
        ```
        <details><summary><img alt="Outside diff"> Missing source</summary>Unanchored.</details>
        <details><summary>⚠️ Outside diff range comments (2)</summary>

        **src/config.py:0**: Invalid line.
        **src/config.py:999999999999999999999999**: Overflow.

        </details>
        """
        #expect(CodeRabbitOutsideDiff.threads(in: [review(body)]).isEmpty)
    }

    // MARK: Private

    private func review(
        _ body: String, id: Int = 7, kind: String = "COMMENTED", authorType: String = "Bot",
    ) -> ReviewComment {
        ReviewComment(id: id, author: "coderabbitai[bot]", body: body, kind: kind, authorType: authorType)
    }
}
