import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct GitHubDiscussionTests {
    @Test(arguments: [true, false], ["Organization", "User"])
    func `discussion source follows repository settings and owner type`(enabled: Bool, type: String) async throws {
        let runner = RecordingRunner()
        runner.standardOutput = """
        {"has_discussions": \(enabled), "full_name": "owner/project", "owner": {"login": "owner", "type": "\(type)"}}
        """
        let repository = Repository(name: "project", path: "/repo", fullName: "owner/project")
        let github = GitHubClient(runner: runner) { true }
        let expected = enabled ? "repo:owner/project" : type == "Organization" ? "org:owner" : ""
        #expect(try await github.discussionScope(repository: repository) == expected)
        let before = runner.commands.count
        #expect(try await github.discussions(repositoryPath: "/repo", scope: "").isEmpty)
        #expect(runner.commands.count == before)
    }

    @Test(arguments: ["repo:owner/project", "org:owner"], ["", "Proposal", "is:closed"])
    func `discussion listings and searches only return open discussions`(scope: String, query: String) async throws {
        let runner = RecordingRunner()
        runner.standardOutput = """
        [{"number":12,"title":"Proposal","closed":false,"url":"https://github.com/owner/community/discussions/12"},
        {"number":13,"title":"Finished","closed":true,"url":"https://github.com/owner/community/discussions/13"}]
        """
        let found = try await GitHubClient(runner: runner) { true }
            .discussions(repositoryPath: "/repo", scope: scope, query: query)
        #expect(found.map(\.id) == ["https://github.com/owner/community/discussions/12"])
        #expect(runner.commands.first?.contains("search=" + scope + " " + query + " is:open sort:updated-desc") == true)
        #expect(runner.commands.first?.contains { $0.contains("number title url closed") } == true)
    }

    @Test
    func `discussion prompts include fetched context without claiming to close an issue`() async throws {
        let runner = RecordingRunner()
        runner.standardOutput = #"{"title":"Proposal","body":"The requested behaviour","url":"#
            + #""https://github.com/owner/community/discussions/12"}"#
        let compose = try await GitHubClient(runner: runner) { true }.discussionPrompt(
            repositoryPath: "/repo", url: "https://github.com/owner/community/discussions/12",
        )
        let prompt = compose("Keep it small")
        #expect(prompt.contains("The requested behaviour"))
        #expect(prompt.contains("https://github.com/owner/community/discussions/12"))
        #expect(prompt.contains("Keep it small"))
        #expect(prompt.contains("Fixes #") == false)
        #expect(prompt.contains("Do not push."))
    }
}
