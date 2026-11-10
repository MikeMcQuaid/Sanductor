import Foundation
import SanductorDomain

extension GitHubClient {
    /// Available diagnostics for the selected failed jobs.
    func autofixPrompt(
        _ candidate: AutofixCandidate,
        summary: PullRequestSummary,
        repositoryPath: String,
    ) async -> String {
        guard candidate.sources.contains(.checks) else {
            return candidate.text
        }

        var sections = [candidate.text]
        let isPublic = await repositoryIsPrivate(repositoryPath: repositoryPath) == false
        let failures = (summary.autofixChecks?.failures ?? []).filter { candidate.events.contains($0.runID) }
        for failure in failures {
            let check = PullRequestCheck(
                name: failure.name,
                status: failure.status,
                conclusion: failure.conclusion,
                requirement: .unknown,
                link: failure.link,
            )
            guard GitHubRemote.fullName(ofURL: failure.link) == GitHubRemote.fullName(ofURL: summary.url),
                  check.canReadLog
            else {
                continue
            }
            guard let log = try? await checkLog(repositoryPath: repositoryPath, check: check) else {
                sections.append("CI · " + failure.name + ": job log not available yet.")
                continue
            }

            sections.append("CI · " + failure.name + "\n[job " + failure.name + "]\n"
                + CheckLogDocument(log).plainText(showTimestamps: false).trimmingCharacters(in: .newlines))
            if isPublic {
                sections.append(failure.link)
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
