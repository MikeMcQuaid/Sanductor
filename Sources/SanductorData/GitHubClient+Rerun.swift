import Foundation
import SanductorDomain

extension GitHubClient {
    struct CheckRerunUnavailable: LocalizedError {
        var errorDescription: String? {
            "GitHub could not identify this failed Actions job. Refresh its checks and try again."
        }
    }

    /// Reruns one failed job or all failures in its workflow, including dependent jobs.
    public func rerunCheck(repositoryPath: String, check: PullRequestCheck, failedOnly: Bool) async throws {
        guard check.canRerun, let runID = check.runID, let repository = GitHubRemote.fullName(ofURL: check.link) else {
            throw CheckRerunUnavailable()
        }

        var arguments = ["run", "rerun", String(runID), "--repo", repository]
        if failedOnly {
            arguments += ["--failed"]
        } else {
            // Check links can carry check-run IDs rather than the job database IDs.
            let result = try await gh(
                ["run", "view", String(runID), "--repo", repository, "--json", "jobs", "--jq", ".jobs"],
                in: repositoryPath,
            )
            let jobs = try JSONDecoder().decode([RunJob].self, from: Data(result.standardOutput.utf8))
            let linked = jobs.filter { $0.url == check.link }
            let matching = linked.isEmpty ? jobs.filter { $0.name == check.name } : linked
            guard matching.count == 1, let job = matching.first else {
                throw CheckRerunUnavailable()
            }

            arguments += ["--job", String(job.databaseId)] // swiftformat:disable:this acronyms
        }
        try await gh(arguments, in: repositoryPath)
    }
}
