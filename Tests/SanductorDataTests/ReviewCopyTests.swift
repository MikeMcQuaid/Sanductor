import SanductorData
import SanductorDomain
import Testing

struct ReviewCopyTests {
    @Test
    func `bulk review copies omit resolved and pending threads`() {
        let open = ReviewThread(id: "open", path: "file", line: 1, isResolved: false, comments: [])
        let pending = ReviewThread(id: "pending", path: "file", line: 1, isResolved: false, comments: [])
        let resolved = ReviewThread(id: "resolved", path: "file", line: 1, isResolved: true, comments: [])
        let local = ReviewThread(id: "local", path: "file", line: 1, isResolved: false, comments: [], resolveID: "")
        let outside = ReviewThread(
            id: "outside",
            path: "file",
            line: 1,
            isResolved: false,
            comments: [],
            resolveID: "",
            outsideDiffReviewID: 1,
        )
        #expect(ReviewCopy.copyable([open, pending, resolved, local, outside]) { $0.id == "pending" }
            == [open, local, outside])
    }

    @Test
    func `copied CodeRabbit comments retain the finding and patch without investigation HTML`() {
        let finding = "**Use a supported setup action.**\n\nThe pinned release cannot install this major version."
        let patch = "```diff\n-old\n+new\n```\n\nApply the same change in the other action."
        let body = """
        <!-- coderabbit-ai-generated:v1 -->
        **<picture><img src="badge.svg" alt=""></picture> Major** · **Functional Correctness** · **Quick win**

        <details><summary><picture><img src="details.svg"></picture> Supported by static analysis</summary>
        <dl><dd>

        Script executed:

        ```bash
        echo investigation
        ```

        </dd></dl></details>

        \(finding)

        <details><summary>Suggested pin update</summary><dl><dd>

        \(patch)

        </dd></dl></details>
        """
        let comment = ReviewThreadComment(author: "coderabbitai", body: body)
        #expect(ReviewCopy.text(comment) == "coderabbitai: " + finding + "\n\n" + patch)
        #expect(comment.body == body)
        #expect(ReviewCopy.text(ReviewThreadComment(author: "alice", body: body)) == "alice: " + body)
    }

    @Test
    func `literal HTML inside a suggested patch survives cleaning`() {
        let body = "**Fix the template.**\n\n```html\n<details><summary>Analysis</summary>Keep</details>"
            + "\n\n\n**Major** keep this literal line\n```"
        #expect(ReviewCopy.text(ReviewThreadComment(author: "coderabbitai", body: body)) == "coderabbitai: " + body)
    }
}
