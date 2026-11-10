import Foundation
import SanductorDomain

/// What a source picker asks GitHub past the newest `pickerLimit`
/// open issues or pull requests it lists: a number directly, since
/// GitHub's search does not match numbers, and anything else through
/// GitHub's search of open titles and bodies. A number that is not
/// open, or not there at all, answers nothing, as does any failure.
extension GitHubClient {
    /// Open issues matching a picker's search.
    func searchOpenIssues(repositoryPath: String, query: String) async -> [IssueSummary] {
        let arguments =
            if let number = ReferencedItemSearch.number(in: query) {
                // GitHub counts a pull request as an issue too; only its
                // URL tells them apart here.
                [
                    "issue", "view", String(number), "--json", "number,title,state,url",
                    "--jq", #"[select(.state == "OPEN" and (.url | contains("/issues/")))]"#,
                ]
            } else {
                [
                    "issue", "list", "--state", "open", "--search", ReferencedItemSearch.searched(query),
                    "--json", "number,title", "--limit", String(Self.pickerLimit),
                ]
            }
        guard let result = try? await gh(arguments, in: repositoryPath, allowFailure: true), result.succeeded,
              let rows = try? JSONDecoder().decode([IssueRow].self, from: Data(result.standardOutput.utf8))
        else {
            return []
        }

        return rows.map { IssueSummary(number: $0.number, title: $0.title) }
    }

    /// Open pull requests matching a picker's search, with the light
    /// fields the picker's own listing has.
    func searchOpenPullRequests(repositoryPath: String, query: String) async -> [PullRequestSummary] {
        let arguments =
            if let number = ReferencedItemSearch.number(in: query) {
                ["pr", "view", String(number), "--json", Self.coreFields, "--jq", #"[select(.state == "OPEN")]"#]
            } else {
                [
                    "pr", "list", "--state", "open", "--search", ReferencedItemSearch.searched(query),
                    "--json", Self.coreFields, "--limit", String(Self.pickerLimit),
                ]
            }
        guard let result = try? await gh(arguments, in: repositoryPath, allowFailure: true), result.succeeded else {
            return []
        }

        return await Self.summaries(
            fromJSON: result.standardOutput,
            requiredChecks: { _ in nil },
            askedForChecks: false,
        )
    }
}
