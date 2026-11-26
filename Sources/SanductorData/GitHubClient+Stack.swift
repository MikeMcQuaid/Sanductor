import Foundation
import SanductorDomain

public extension GitHubClient {
    /// Reads only the current PR number for each stack layer, bottom first.
    internal func openStackNumbers(repositoryPath: String, branches: [String]) async throws -> [Int] {
        let data = try await queryStackBranches(repositoryPath: repositoryPath, branches: branches) { variable in
            variable + ": pullRequests(headRefName: $" + variable + ", states: OPEN, first: 1, "
                + "orderBy: { field: CREATED_AT, direction: DESC }) { nodes { number } }"
        } result: { variables in
            "[" + variables.lazy.map { "." + $0 + ".nodes[0].number" }.joined(separator: ", ") + "]"
        }
        return try JSONDecoder().decode([Int?].self, from: data).compactMap(\.self)
    }

    internal struct StackReview: Decodable {
        let state: String
        let headRefName: String
        let headRefOid: String?
    }

    /// Reads dependent PRs, known heads and official stack members even after GitHub retargets them.
    internal func stackReviews(
        repositoryPath: String, branches: [String], registered: PullRequestSummary?,
    ) async throws -> [StackReview] {
        let fields = "{ state headRefName headRefOid }"
        var numbered = ""
        if let registered {
            let stacks = try await stacks(containing: registered.number, in: repositoryPath)
            let stackNumber = registered.stackStanding?.number
            let members = stacks.filter { stackNumber == nil || $0.number == stackNumber }
                .flatMap { $0.pullRequests.map(\.number) }
            numbered = Set(members)
                .sorted()
                .map { number in
                    "pr" + String(number) + ": pullRequest(number: " + String(number) + ") " + fields
                }
                .joined(separator: " ")
        }
        let data = try await queryStackBranches(
            repositoryPath: repositoryPath, branches: branches, extra: numbered,
        ) { variable in
            let open = ": $" + variable + ", states: OPEN, first: 100) { nodes " + fields + " } "
            return variable + "Heads: pullRequests(headRefName" + open
                + variable + "Bases: pullRequests(baseRefName" + open
                + variable + "Merged: pullRequests(headRefName: $" + variable + ", states: MERGED, first: 1, "
                + "orderBy: { field: CREATED_AT, direction: DESC }) { nodes " + fields + " }"
        } result: { _ in "[.[] | select(. != null) | if has(\"nodes\") then .nodes[] else . end]" }
        return try JSONDecoder().decode([StackReview].self, from: data)
    }

    private func queryStackBranches(
        repositoryPath: String,
        branches: [String],
        extra: String = "",
        field: (String) -> String,
        result: ([String]) -> String,
    ) async throws -> Data {
        let variables = branches.indices.map { "branch" + String($0) }
        let definition = variables.lazy.map { "$" + $0 + ": String!" }.joined(separator: ", ")
        let query = "query($owner: String!, $repo: String!, " + definition + ") { "
            + "repository(owner: $owner, name: $repo) { "
            + variables.map(field).joined(separator: " ") + " " + extra + " } }"
        let response = try await gh(
            ["api", "graphql", "-F", "owner={owner}", "-F", "repo={repo}", "-f", "query=" + query]
                + zip(variables, branches).flatMap { ["-f", $0 + "=" + $1] }
                + ["--jq", ".data.repository | " + result(variables)],
            in: repositoryPath,
        )
        return Data(response.standardOutput.utf8)
    }

    /// Creates or extends a GitHub stack without changing existing membership.
    /// Numbers arrive bottom first, which need not be numerical order.
    func linkStack(worktreePath: String, numbers: [Int]) async throws {
        guard Set(numbers).count == numbers.count else {
            throw SessionServiceError("A pull request cannot appear twice in a stack.")
        }
        guard numbers.count > 1 else {
            return
        }

        let path = "repos/{owner}/{repo}/stacks"
        var existing: GitHubStack?
        for number in numbers where existing?.pullRequests.contains(where: { $0.number == number }) != true {
            for stack in try await stacks(containing: number, in: worktreePath) where stack.open {
                guard existing == nil || existing?.number == stack.number else {
                    throw SessionServiceError("These pull requests belong to different GitHub stacks.")
                }

                existing = stack
            }
        }

        var missing = numbers
        var destination = path
        if let existing {
            let members = existing.pullRequests.map(\.number)
            let positions = numbers.compactMap { members.firstIndex(of: $0) }
            guard positions == positions.sorted() else {
                throw SessionServiceError("The pull request order differs from the existing GitHub stack.")
            }

            missing = numbers.filter { members.contains($0) == false }
            guard missing.isEmpty == false else {
                return
            }
            guard let top = members.last, let index = numbers.firstIndex(of: top),
                  Array(numbers.suffix(from: index + 1)) == missing,
                  numbers.prefix(through: index).allSatisfy({ members.contains($0) })
            else {
                throw SessionServiceError("New pull requests must follow the top of the existing GitHub stack.")
            }

            destination += "/" + String(existing.number) + "/add"
        }
        try await gh(
            ["api", "--method", "POST"] + Self.stackHeaders + [destination]
                + missing.flatMap { ["--field", "pull_requests[]=" + String($0)] },
            in: worktreePath,
        )
    }

    private static let stackHeaders = [
        "--header", "Accept: application/vnd.github+json",
        "--header", "X-GitHub-Api-Version: 2026-03-10",
    ]

    private func stacks(containing number: Int, in path: String) async throws -> [GitHubStack] {
        let result = try await gh(
            ["api", "repos/{owner}/{repo}/stacks?pull_request=" + String(number)] + Self.stackHeaders, in: path,
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GitHubStack].self, from: Data(result.standardOutput.utf8))
    }
}

// MARK: - GitHubStack

private struct GitHubStack: Decodable {
    struct PullRequest: Decodable {
        let number: Int
    }

    let number: Int
    let open: Bool
    let pullRequests: [PullRequest]
}
