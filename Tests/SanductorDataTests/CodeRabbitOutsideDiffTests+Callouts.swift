@testable import SanductorData
import SanductorDomain
import Testing

extension CodeRabbitOutsideDiffTests {
    @Test
    func `callout findings use their full file anchor and retain copyable feedback`() throws {
        let threads = CodeRabbitOutsideDiff.threads(in: [Self.calloutReview])
        #expect(threads.count == 1)
        let thread = try #require(threads.first)
        #expect(thread.path == "Library/Homebrew/bundle/cask.rb")
        #expect(thread.line == 109)
        #expect(thread.outsideDiffReviewID == 1)
        #expect(thread.resolveID.isEmpty)
        #expect(ReviewCopy.text(thread).contains("Forward `--adopt` to the reinstall installer"))
        #expect(ReviewCopy.text(thread).contains("including the fallback construction path"))
        #expect(ReviewCopy.text(thread).contains("Review info") == false)
    }

    @Test
    func `callout findings join current head automated review summaries`() throws {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixBots = true
        let candidate = try #require(AutofixCandidate.reviewSummaries(
            [Self.calloutReview], head: "head", state: state,
        ))
        #expect(candidate.events == ["review:review"])
        #expect(candidate.text.contains("Library/Homebrew/bundle/cask.rb:109-116"))
        #expect(candidate.text.contains("including the fallback construction path"))
        #expect(candidate.text.contains("Review info") == false)
        #expect(AutofixCandidate.reviewSummaries([Self.calloutReview], head: "other", state: state) == nil)
    }

    @Test
    func `callout examples and unrelated disclosures cannot create findings`() {
        var review = Self.calloutReview
        review = ReviewComment(
            id: 8,
            author: review.author,
            body: "````markdown\n" + review.body + "\n````",
            kind: review.kind,
            authorType: review.authorType,
        )
        #expect(CodeRabbitOutsideDiff.threads(in: [review]).isEmpty)
        review = ReviewComment(
            id: 9,
            author: review.author,
            body: Self.calloutReview.body.replacing("Outside diff range comments", with: "Review info"),
            kind: review.kind,
            authorType: review.authorType,
        )
        #expect(CodeRabbitOutsideDiff.threads(in: [review]).isEmpty)
    }

    @Test(arguments: ["before", "after", "both"], ["Nitpick comments", "Outside diff range comments"])
    func `matched sections include surrounding callouts once`(position: String, heading: String) throws {
        let section = """
        <details><summary>\(heading) (1)</summary><blockquote>

        **other.rb:42**: Retain this section finding.

        </blockquote></details>
        """
        let body = (position == "after" ? "" : Self.calloutReview.body + "\n\n")
            + section
            + (position == "after"
                ? "\n\n<details><summary>ℹ️ Review info</summary>Ignore this metadata.</details>" : "")
            + (position == "before" ? "" : "\n\n" + Self.calloutReview.body)
        let review = ReviewComment(
            id: 1,
            author: Self.calloutReview.author,
            body: body,
            kind: Self.calloutReview.kind,
            nodeID: Self.calloutReview.nodeID,
            authorType: Self.calloutReview.authorType,
            commit: Self.calloutReview.commit,
        )
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.autofixBots = true
        let candidate = try #require(AutofixCandidate.reviewSummaries([review], head: "head", state: state))
        #expect(candidate.text.components(separatedBy: "including the fallback construction path").count == 2)
        #expect(candidate.text.components(separatedBy: "Retain this section finding.").count == 2)
        #expect(candidate.text.contains("Review info") == false)
        #expect(AutofixCandidate.reviewSummaries([review], head: "other", state: state) == nil)
    }

    private static var calloutReview: ReviewComment {
        ReviewComment(
            id: 1,
            author: "coderabbitai[bot]",
            body: """
            <!-- coderabbit-ai-generated:v1 -->

            > [!CAUTION]
            > Some comments are outside the diff and can’t be posted inline due to GitHub limitations.
            >
            > **⚠️ Outside diff range comments (1)**
            >
            > <details>
            > <summary><strong><picture><img src="major.svg" alt=""></picture> Major</strong> · \
            Forward <code>--adopt</code> to the reinstall installer · <code>cask.rb:109-116</code></summary><blockquote>
            > <dl><dd><br>
            >
            > `Library/Homebrew/bundle/cask.rb:109-116`
            > **<picture><img src="major.svg" alt=""></picture> Major** · **Functional Correctness** · **Quick win**
            >
            > **Forward `--adopt` to the reinstall installer**
            >
            > When the new tap targets an existing matching app that the old cask does not own, \
            the old cask is uninstalled and the reinstall fails on the occupied target. \
            Pass `args.adopt?` to the reinstall installer, including the fallback construction path.
            >
            > <!-- cr-comment:v1:example -->
            >
            > </dd></dl>
            > </blockquote></details>

            <h6><details><summary>Review info</summary>Not a finding.</details></h6>
            """,
            kind: "COMMENTED",
            nodeID: "review",
            authorType: "Bot",
            commit: "head",
        )
    }
}
