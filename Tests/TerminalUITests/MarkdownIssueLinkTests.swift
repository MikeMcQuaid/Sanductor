import Foundation
@testable import TerminalUI
import Testing

@MainActor
struct MarkdownIssueLinkTests {
    @Test
    func `references retain their formatting across paragraphs and lists`() {
        let content = MarkdownText.content(
            """
            Fixes #1

            #2

            - #3
            - #**4**
            """,
            repositoryURL: URL(string: "https://github.com/owner/repo"),
        )
        #expect(Set(content.runs.compactMap(\.link).map(\.absoluteString)) == Set((1 ... 4).map { number in
            "https://github.com/owner/repo/issues/" + String(number)
        }))
    }

    @Test(arguments: ["https://github.com/owner/repo", "https://github.example.com/team/project"])
    func `issue references link to the current repository`(repository: String) throws {
        let url = try #require(URL(string: repository))
        let content = MarkdownText.content("Fixes #1234 and **#5678**.", repositoryURL: url)
        #expect(String(content.characters) == "Fixes #1234 and #5678.")
        #expect(content.runs.contains { $0.link?.absoluteString == repository + "/issues/1234" })
        #expect(content.runs.contains { run in
            run.link?.absoluteString == repository + "/issues/5678"
                && run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        #expect(MarkdownText.content("Fixes #1234 and **#5678**.").runs.allSatisfy { $0.link == nil })
    }

    @Test
    func `code links images and nonreferences stay unchanged`() {
        let content = MarkdownText.content(
            """
            `#1234` and [#5678](https://example.com) and ![#9012](image.png).

            ```ruby
            #3456
            ```

                #7890

            word#12 #0 #123abc owner/repo#34 https://example.com/#56
            """,
            repositoryURL: URL(string: "https://github.com/owner/repo"),
        )
        #expect(content.runs.compactMap(\.link).map(\.absoluteString) == [
            "https://example.com", "https://example.com/#56",
        ])
    }
}
