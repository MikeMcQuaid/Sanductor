import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension GitHubClientTests {
    @Test(arguments: ["false", "true", "null"])
    func `phone status uses existing host reads regardless of repository visibility`(visibility: String) async throws {
        let runner = RecordingRunner()
        runner.standardOutput = """
        {"number":42,"title":"Private title","url":"https://github.com/owner/repo/pull/42",
         "headRefName":"work","state":"OPEN","private":\(visibility),
         "reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"state":"FAILURE"}]}
        """
        let summary = try #require(await GitHubClient(runner: runner) { true }.pullRequestSummary(
            repositoryPath: "/repo", number: 42,
        ))
        let projection = SidebarPullRequest(summary)
        #expect(projection.details?.state == "OPEN")
        #expect(projection.details?.checks == "FAILURE")
        #expect(projection.details?.reviewDecision == "CHANGES_REQUESTED")
        #expect(runner.commands.count == 1)
        #expect(runner.commands.first?.starts(with: ["gh", "pr", "view", "42"]) == true)
    }

    @Test
    func `older PR caches can share status without a visibility field`() throws {
        let summary = try JSONDecoder().decode(PullRequestSummary.self, from: Data(#"""
        {"number":42,"title":"Old","url":"https://github.com/owner/repo/pull/42","headBranch":"work",
         "state":"MERGED","reviewDecision":"APPROVED","checks":"SUCCESS"}
        """#.utf8))
        let projection = SidebarPullRequest(summary)
        #expect(projection.details?.stateLabel == "Merged")
        #expect(projection.details?.checks == "SUCCESS")
        #expect(projection.details?.reviewDecision == "APPROVED")
    }
}
