import Foundation
import SanductorDomain

public extension GitHubClient {
    /// Repository discussions take precedence; only organisations provide a fallback.
    func discussionScope(repository: Repository) async throws -> String {
        guard let name = repository.fullName, name.isEmpty == false else {
            return ""
        }

        let result = try await gh(["api", "repos/" + name, "--cache", "1h"], in: repository.path)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let source = try decoder.decode(DiscussionRepository.self, from: Data(result.standardOutput.utf8))
        if source.hasDiscussions {
            return "repo:" + source.fullName
        }
        return source.owner.type == "Organization" ? "org:" + source.owner.login : ""
    }

    /// Organisation discussions live in a source repository and appear in this search too.
    func discussions(repositoryPath: String, scope: String, query: String = "") async throws -> [DiscussionSummary] {
        guard scope.isEmpty == false else {
            return []
        }

        let result = try await gh([
            "api", "graphql", "-f",
            "query=query($search: String!) { search(query: $search, type: DISCUSSION, first: \(Self.pickerLimit)) "
                + "{ nodes { ... on Discussion { number title url closed } } } }",
            "-f", "search=" + scope + " " + query + " is:open sort:updated-desc",
            "--jq", ".data.search.nodes",
        ], in: repositoryPath)
        return try JSONDecoder()
            .decode([DiscussionSummary].self, from: Data(result.standardOutput.utf8))
            .filter { $0.closed == false }
    }

    /// Fetches the selected discussion as context for an editable task.
    func discussionPrompt(repositoryPath: String, url: String, context: String) async throws -> String {
        let result = try await gh([
            "api", "graphql", "-f",
            "query=query($url: URI!) { resource(url: $url) { ... on Discussion { title body url } } }",
            "-f", "url=" + url, "--jq", ".data.resource",
        ], in: repositoryPath)
        let discussion = try JSONDecoder().decode(DiscussionBody.self, from: Data(result.standardOutput.utf8))
        return Self.prompt(
            heading: "Work on discussion: " + discussion.title + "\n" + discussion.url,
            body: discussion.body,
            context: context,
            closing: "Commit your work, referencing the discussion URL. Do not push.",
        )
    }
}

// MARK: - DiscussionBody

private struct DiscussionBody: Decodable {
    let title: String
    let body: String
    let url: String
}

// MARK: - DiscussionRepository

private struct DiscussionRepository: Decodable {
    struct Owner: Decodable {
        let login: String
        let type: String
    }

    let hasDiscussions: Bool
    let fullName: String
    let owner: Owner
}
