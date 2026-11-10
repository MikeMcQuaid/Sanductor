@testable import SanductorData
import SanductorDomain
import Testing

extension GitHubClientTests {
    @Test(arguments: ["success", "failure", "cancelled", ""])
    func `only successful maintenance steps are omitted from check logs`(conclusion: String) async throws {
        let runner = ScriptedGitHubRunner(answers: [
            "gh run view 9 --repo upstream/repo --json jobs --jq .jobs": .success(
                #"""
                [{"databaseId": 99, "name": "build", "steps": [{"name": "Set up job", "conclusion": "\#(conclusion)",
                   "startedAt": "2026-11-10T10:00:00Z", "completedAt": "2026-11-10T10:00:03Z"},
                  {"name": "Run tests", "conclusion": "success",
                   "startedAt": "2026-11-10T10:00:03Z", "completedAt": "2026-11-10T10:00:06Z"},
                  {"name": "Post actions/checkout", "conclusion": "\#(conclusion)",
                   "startedAt": "2026-11-10T10:00:06Z", "completedAt": "2026-11-10T10:00:09Z"},
                  {"name": "Post cache", "conclusion": "success",
                   "startedAt": "2026-11-10T10:00:09Z", "completedAt": "2026-11-10T10:00:12Z"},
                  {"name": "Complete job", "conclusion": "\#(conclusion)",
                   "startedAt": "2026-11-10T10:00:12Z", "completedAt": "2026-11-10T10:00:15Z"}]}]
                """#,
            ),
            "gh api --allow-escape-sequences repos/upstream/repo/actions/jobs/99/logs": .success("""
            2026-11-10T10:00:00.100Z setup boundary
            2026-11-10T10:00:00.200Z ##[group]Runner details
            2026-11-10T10:00:01.100Z runner setup noise
            2026-11-10T10:00:02.100Z ##[endgroup]
            2026-11-10T10:00:03.100Z tests boundary
            2026-11-10T10:00:04.100Z test output
            2026-11-10T10:00:06.100Z cleanup boundary
            2026-11-10T10:00:07.100Z checkout cleanup noise
            2026-11-10T10:00:10.100Z ##[warning]Cache upload failed
            2026-11-10T10:00:11.100Z cache diagnostic context
            2026-11-10T10:00:13.100Z job completion noise
            untimed diagnostic
            """),
        ])
        let log = try await GitHubClient(runner: runner) { true }.checkLog(
            repositoryPath: "/fork",
            check: PullRequestCheck(
                name: "build",
                status: "COMPLETED",
                conclusion: "FAILURE",
                requirement: .required,
                link: "https://github.com/upstream/repo/actions/runs/9/job/11",
            ),
        )
        for noise in ["runner setup noise", "checkout cleanup noise", "job completion noise"] {
            #expect(log.contains(noise) == (conclusion != "success"))
        }
        for kept in ["setup", "tests", "cleanup"] {
            #expect(log.contains(kept + " boundary"))
        }
        for kept in ["test output", "Cache upload failed", "cache diagnostic context", "untimed diagnostic"] {
            #expect(log.contains(kept))
        }
        #expect(CheckLogDocument(log).lines.first { $0.text == "test output" }?.depth == 0)
    }

    @Test
    func `job logs containing NUL separated filenames remain readable and copyable`() async throws {
        let runner = ScriptedGitHubRunner(answers: [
            "gh api --allow-escape-sequences repos/{owner}/{repo}/actions/jobs/11/logs": .success("""
            2026-11-10T13:40:24.1852140Z ##[group]Listing files
            2026-11-10T13:40:24.1852154Z [command]git ls-files -z
            2026-11-10T13:40:24.1978548Z \u{1B}[32mREADME.md\0file.swift\0\u{1B}[0m
            2026-11-10T13:40:24.2025786Z ##[endgroup]
            2026-11-10T13:40:24.2030000Z unexpected\0separator
            2026-11-10T13:40:24.2046313Z ##[error]No test report files were found
            """),
        ])
        let log = try await GitHubClient(runner: runner) { true }.jobLog(repositoryPath: "/repo", jobID: 11)
        let document = CheckLogDocument(log)
        #expect(document.plainText(showTimestamps: false) == """
        Listing files
          git ls-files -z
        unexpected separator
        Error: No test report files were found
        """)
        #expect(document.plainText(showTimestamps: true)
            .contains("2026-11-10T13:40:24.2030000Z unexpected separator"))
        #expect(log.contains("\0") == false)
        #expect(log.contains("README.md") == false)
    }

    @Test(arguments: [11, 99], ["", "?pr=7"])
    func `finished check logs resolve job IDs in the checks repository`(linkedID: Int, query: String) async throws {
        let runner = ScriptedGitHubRunner(answers: [
            "gh api --allow-escape-sequences repos/{owner}/{repo}/actions/jobs/" + String(linkedID) + "/logs":
                .failure("HTTP 404: Not Found"),
            "gh run view 9 --repo upstream/repo --json jobs --jq .jobs": .success(
                #"""
                [{"databaseId": 88, "name": "build",
                  "url": "https://github.com/upstream/repo/actions/runs/9/job/22"},
                 {"databaseId": 99, "name": "build",
                  "url": "https://github.com/UPSTREAM/REPO/actions/runs/9/job/\#(linkedID)"}]
                """#,
            ),
            "gh api --allow-escape-sequences repos/upstream/repo/actions/jobs/99/logs":
                .success("2026-11-10T10:00:00Z \u{1B}[32mcomplete log\u{1B}[0m\n"),
        ])
        let log = try await GitHubClient(runner: runner) { true }.checkLog(
            repositoryPath: "/fork",
            check: PullRequestCheck(
                name: "build",
                status: "COMPLETED",
                conclusion: "SUCCESS",
                requirement: .required,
                link: "https://github.com/upstream/repo/actions/runs/9/job/" + String(linkedID) + query,
            ),
        )
        #expect(log == "2026-11-10T10:00:00Z complete log\n")
    }
}
