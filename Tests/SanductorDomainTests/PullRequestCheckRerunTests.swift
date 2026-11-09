import SanductorDomain
import Testing

struct PullRequestCheckRerunTests {
    @Test(arguments: ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED"])
    func `finished failed Actions jobs can be rerun`(conclusion: String) {
        let check = PullRequestCheck(
            name: "build",
            status: "COMPLETED",
            conclusion: conclusion,
            requirement: .optional,
            link: "https://github.com/o/r/actions/runs/123/job/456?pr=7",
        )
        #expect(check.runID == 123)
        #expect(check.canRerun)
    }

    @Test(arguments: [
        ("IN_PROGRESS", "https://github.com/o/r/actions/runs/123/job/456"),
        ("COMPLETED", "https://ci.example.com/o/r/actions/runs/123/job/456"),
        ("COMPLETED", "https://github.com/o/r/actions/runs/0/job/456"),
        ("COMPLETED", "https://github.com/o/r/actions/runs/abc/job/456"),
        ("COMPLETED", "https://github.com/o/r/runs/123"),
        ("EXPECTED", ""),
    ])
    func `unfinished external and unidentified checks cannot be rerun`(status: String, link: String) {
        #expect(PullRequestCheck(
            name: "build", status: status, conclusion: "FAILURE", requirement: .required, link: link,
        ).canRerun == false)
    }
}
