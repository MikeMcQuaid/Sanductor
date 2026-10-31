import AppKit
import Foundation
@testable import PRFeature
import SanductorData
import TerminalUI
import Testing

/// Complete failing logs and recoverable failures from the copy action.
extension PullRequestsModelTests {
    @Test(arguments: [false, true])
    func `copying logs clears stale clipboard contents before fetching`(fails: Bool) async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("stale text", forType: .string)
        let model = makeModel()
        model.fetchFailedRunLog = { _ in
            #expect(pasteboard.string(forType: .string) == nil)
            if fails {
                throw GitHubClient.RunLogsUnavailable(failedJobs: 1)
            }
            return "failure details"
        }

        let copied = await model.copyFailingLogs(
            summary(1, head: "feature", failingCheckLinks: ["https://github.com/o/r/actions/runs/123/job/1"]),
            pasteboard: pasteboard,
        )
        #expect(copied == !fails)
        #expect(pasteboard.string(forType: .string) == (fails ? nil : "## Run 123\nfailure details"))
    }

    @Test
    func `failing logs gather every line from each run once`() async throws {
        let links = [
            "https://github.com/o/r/actions/runs/123/job/1",
            "https://github.com/o/r/actions/runs/123/job/2",
            "https://ci.example.invalid/build/9",
            "https://github.com/o/r/actions/runs/456/job/3",
        ]
        #expect(PullRequestsModel.runIDs(in: links) == [123, 456])

        let model = makeModel()
        let long = (1 ... 300).map { "line " + String($0) }.joined(separator: "\n")
        model.fetchFailedRunLog = { runID in runID == 123 ? long : "short" }
        let text = try await model.failingLogs(for: summary(1, head: "feature", failingCheckLinks: links))
        #expect(text == "## Run 123\n" + long + "\n\n## Run 456\nshort")
    }

    @Test
    func `a run with nothing readable never sinks the ones that have logs`() async throws {
        let links = [
            "https://github.com/o/r/actions/runs/123/job/1",
            "https://github.com/o/r/actions/runs/456/job/3",
        ]
        let model = makeModel()
        // The first run has nothing to give yet; the second does,
        // and that is what the prompt is for.
        model.fetchFailedRunLog = { runID in
            guard runID == 456 else {
                throw GitHubClient.RunLogsUnavailable(failedJobs: 1)
            }

            return "it broke here"
        }
        let text = try await model.failingLogs(for: summary(1, head: "feature", failingCheckLinks: links))
        #expect(text == "## Run 456\nit broke here")
    }

    @Test
    func `only every run coming back empty is worth saying, in our words`() async {
        let links = ["https://github.com/o/r/actions/runs/123/job/1"]
        let model = makeModel()
        model.fetchFailedRunLog = { _ in throw GitHubClient.RunLogsUnavailable(failedJobs: 2) }

        #expect(await model.copyFailingLogs(summary(1, head: "feature", failingCheckLinks: links)) == false)
        let message = ErrorLog.shared.entries.last?.message ?? ""
        #expect(message.contains("2 failed jobs"))
        // gh's own "still in progress" never reaches the pane.
        #expect(message.contains("still in progress") == false)
        #expect(message.contains("failed:") == false)
    }

    @Test
    func `a failure waiting cannot cure is not reported as a wait`() async {
        let links = ["https://github.com/o/r/actions/runs/123/job/1"]
        let model = makeModel()
        let refusal = NSError(domain: "gh", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "there is no route to the network right now",
        ])
        model.fetchFailedRunLog = { _ in throw refusal }

        #expect(await model.copyFailingLogs(summary(1, head: "feature", failingCheckLinks: links)) == false)
        let message = ErrorLog.shared.entries.last?.message ?? ""
        #expect(message.contains("no route to the network"))
        #expect(message.contains("yet") == false)
    }

    @Test
    func `copies preserve complete logs and their job labels`() async throws {
        let stamp = "2026-08-30T12:40:20.1479947Z "
        let log = [
            "tests (ubuntu-latest)\tCheck code styles\t\u{FEFF}" + stamp + "##[group]Run brew install shellcheck",
            "tests (ubuntu-latest)\tCheck code styles\t" + stamp + "\u{1B}[36;1mbrew install shellcheck\u{1B}[0m",
            "tests (ubuntu-latest)\tCheck code styles\t" + stamp + "error: style",
        ].joined(separator: "\n")
        // Copies keep the complete source for oversized file delivery.
        let model = makeModel()
        model.fetchFailedRunLog = { runID in
            runID == 1 ? log : log + "\nbuild\tCompile\t" + stamp + "error: compile"
        }
        let first = summary(1, head: "f", failingCheckLinks: ["https://x/actions/runs/1"])
        let one = try await model.failingLogs(for: first)
        #expect(one == "## Run 1\n" + log)
        let second = summary(1, head: "f", failingCheckLinks: ["https://x/actions/runs/2"])
        let two = try await model.failingLogs(for: second)
        #expect(two == "## Run 2\n" + log + "\nbuild\tCompile\t" + stamp + "error: compile")
    }
}
