import Foundation
@testable import PRFeature
import SanductorDomain
import Testing

extension PullRequestsModelTests {
    @Test
    func `bulk reruns include optional failures once per workflow and refresh shared state`() async {
        let model = makeModel()
        var summary = summary(7, head: "feature", checks: "FAILURE")
        summary.checkDetails = [rerunCheck(1, job: 11), rerunCheck(1, job: 12), rerunCheck(2, job: 21)]
        model.selected = summary
        model.summaries = [summary]
        var requested = [Int]()
        model.performCheckRerun = { check, failedOnly in
            #expect(failedOnly)
            #expect(model.isRerunningChecks)
            try requested.append(#require(check.runID))
        }
        let refreshed = self.summary(7, head: "feature", checks: "PENDING")
        model.fetchSummary = { number in
            #expect(number == 7)
            #expect(requested == [1, 2])
            return refreshed
        }

        #expect(await model.rerunChecks(summary))
        #expect(model.isRerunningChecks == false)
        #expect(model.selected?.checks == "PENDING")
        #expect(model.summaries.first?.checks == "PENDING")
        #expect(model.pullRequests.cachedSummary(repositoryPath: "/repo", number: 7)?.checks == "PENDING")
    }

    @Test
    func `individual reruns target one job and reject overlapping requests`() async {
        let model = makeModel()
        var summary = summary(7, head: "feature")
        let check = rerunCheck(1, job: 11)
        summary.checkDetails = [check, rerunCheck(1, job: 12)]
        var requests = 0
        model.performCheckRerun = { requested, failedOnly in
            requests += 1
            #expect(requested == check)
            #expect(failedOnly == false)
            #expect(await model.rerunChecks(summary) == false)
        }
        #expect(await model.rerunChecks(summary, check: check))
        #expect(requests == 1)
        #expect(model.isRerunningChecks == false)
    }

    @Test
    func `a rejected rerun does not prevent other workflows or a summary refresh`() async {
        let model = makeModel()
        var summary = summary(7, head: "feature")
        summary.checkDetails = [rerunCheck(1, job: 11), rerunCheck(2, job: 21)]
        var requested = [Int]()
        var refreshed = false
        model.performCheckRerun = { check, _ in
            try requested.append(#require(check.runID))
            if check.runID == 1 {
                throw URLError(.cannotConnectToHost)
            }
        }
        model.fetchSummary = { _ in
            refreshed = true
            return nil
        }
        #expect(await model.rerunChecks(summary) == false)
        #expect(requested == [1, 2])
        #expect(refreshed)
        #expect(model.isRerunningChecks == false)
    }

    @Test(arguments: ["SUCCESS", "NEUTRAL", "SKIPPED", ""])
    func `checks without failures cannot be rerun`(conclusion: String) async {
        let model = makeModel()
        var summary = summary(7, head: "feature")
        summary.checkDetails = [
            PullRequestCheck(
                name: "build",
                status: "COMPLETED",
                conclusion: conclusion,
                requirement: .required,
                link: "https://github.com/o/r/actions/runs/1/job/11",
            ),
        ]
        model.performCheckRerun = { _, _ in Issue.record("No failed jobs to rerun") }
        #expect(await model.rerunChecks(summary) == false)
    }

    private func rerunCheck(_ run: Int, job: Int) -> PullRequestCheck {
        PullRequestCheck(
            name: "Job " + String(job),
            status: "COMPLETED",
            conclusion: "FAILURE",
            requirement: .optional,
            link: "https://github.com/o/r/actions/runs/" + String(run) + "/job/" + String(job),
        )
    }
}
