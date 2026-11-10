import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

/// Exercises what the issue and pull request pickers ask GitHub past
/// their own lists.
struct GitHubClientPickerSearchTests {
    @Test
    func `picker searches look numbers up and send text to GitHub's search`() async {
        let runner = RecordingRunner()
        let client = GitHubClient(runner: runner) { true }
        _ = await client.searchOpenIssues(repositoryPath: "/repo", query: " #12345\n")
        _ = await client.searchOpenIssues(repositoryPath: "/repo", query: "fork crash")
        _ = await client.searchOpenPullRequests(repositoryPath: "/repo", query: "12345")
        _ = await client.searchOpenPullRequests(repositoryPath: "/repo", query: "#fork crash")
        #expect(runner.commands.map { Array($0.prefix(4)) } == [
            ["gh", "issue", "view", "12345"],
            ["gh", "issue", "list", "--state"],
            ["gh", "pr", "view", "12345"],
            ["gh", "pr", "list", "--state"],
        ])
        let searched = runner.commands.filter { $0.contains("--search") }
        #expect(searched.count == 2)
        #expect(searched.allSatisfy { $0.contains("fork crash") && $0.contains("open") && $0.contains("50") })
    }

    @Test
    func `picker searches decode what GitHub answers`() async {
        let runner = RecordingRunner()
        let client = GitHubClient(runner: runner) { true }
        runner.standardOutput = #"[{"number": 4321, "title": "Old issue"}]"#
        let issues = await client.searchOpenIssues(repositoryPath: "/repo", query: "4321")
        #expect(issues == [IssueSummary(number: 4_321, title: "Old issue")])

        runner.standardOutput = """
        [{"number": 8765, "title": "Old work", "url": "https://github.com/o/r/pull/8765",
          "headRefName": "old", "baseRefName": "main", "state": "OPEN"}]
        """
        let pullRequests = await client.searchOpenPullRequests(repositoryPath: "/repo", query: "old work")
        #expect(pullRequests.map(\.number) == [8_765])
        #expect(pullRequests.map(\.headBranch) == ["old"])

        runner.standardOutput = ""
        #expect(await client.searchOpenIssues(repositoryPath: "/repo", query: "gone").isEmpty)
    }
}
