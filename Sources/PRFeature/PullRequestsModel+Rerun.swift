import SanductorDomain

extension PullRequestsModel {
    func rerunChecks(_ summary: PullRequestSummary, check: PullRequestCheck? = nil) async -> Bool {
        let checks = (summary.checkDetails ?? []).filter { candidate in
            candidate.canRerun && (check == nil || candidate.id == check?.id)
        }
        guard isRerunningChecks == false, checks.isEmpty == false else {
            return false
        }

        isRerunningChecks = true
        defer { isRerunningChecks = false }
        var runs = Set<Int>()
        var succeeded = true
        for candidate in checks {
            guard let runID = candidate.runID, runs.insert(runID).inserted else {
                continue
            }

            do {
                try await performCheckRerun(candidate, check == nil)
                note("Requested " + (check == nil ? "failed jobs in " : "")
                    + candidate.displayName + " to rerun for #" + String(summary.number) + ".")
            } catch {
                report("Could not rerun " + candidate.displayName + " for #" + String(summary.number)
                    + ": " + error.localizedDescription)
                succeeded = false
            }
        }
        pullRequests.invalidate(repositoryPath: repository.path, number: summary.number)
        pullRequests.invalidateListings(repositoryPath: repository.path)
        await refreshSummary(summary.number)
        return succeeded
    }
}
