import Observation
@testable import PRFeature
import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension PullRequestStackTests {
    @Test(arguments: PullRequestScope.allCases)
    func `a lower branch listing enables publication and notifies observers in every scope`(
        scope: PullRequestScope,
    ) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(
            items: [fixtures.item(branch: "feature", ahead: 1)], runner: StackListingRunner(),
        )
        model.scope = scope
        model.stacking.stack = BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        model.stacking.selected = "upper"
        model.stacking.unpushedBranches = ["lower", "upper"]
        let changed = Mutex(false)
        withObservationTracking {
            #expect(model.canPublish == false)
        } onChange: {
            changed.withLock { $0 = true }
        }

        await model.prefetchStack()?.value

        #expect(model.hasOpenPullRequest("lower"))
        #expect(model.canPublish)
        #expect(changed.withLock { $0 })
        changed.withLock { $0 = false }
        withObservationTracking {
            #expect(model.canPublish)
        } onChange: {
            changed.withLock { $0 = true }
        }
        await model.prefetchStack()?.value
        #expect(changed.withLock { $0 } == false)
    }
}

// MARK: - StackListingRunner

private struct StackListingRunner: ProcessRunner {
    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        if arguments.contains("get-url") {
            return ProcessResult(status: 0, standardOutput: "https://github.com/owner/repo.git\n", standardError: "")
        }
        if arguments.contains(where: { $0.contains("/pulls?") && $0.contains("lower") }) {
            return ProcessResult(
                status: 0,
                standardOutput: "HTTP/2.0 200 OK\r\n\r\n"
                    + #"[{"number":1,"title":"Lower","html_url":"","state":"open","head":{"ref":"lower"},"#
                    + #""base":{"ref":"main"}}]"#,
                standardError: "",
            )
        }
        return ProcessResult(status: 1, standardOutput: "", standardError: "Not available")
    }
}
