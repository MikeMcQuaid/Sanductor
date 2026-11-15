import Foundation
@testable import SanductorData
import Testing

struct AgentQuotaDeadlineTests {
    @Test(.timeLimit(.minutes(1)))
    func `a stalled helper and its descendants are killed before returning`() async throws {
        let root = try TestSupport.temporaryDirectory("quota-deadline")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let helper = "trap '' TERM; echo ${$} > " + (root + "/helper").shellQuoted
            + "; /bin/sleep 5 & echo ${!} > " + (root + "/child").shellQuoted + "; wait"
        let result = try await FoundationProcessRunner().run(
            TestSupport.sudoLoginArguments([
                "/bin/zsh", "-fc", SessionService.quotaPayload(
                    "quota_token=$(/bin/sh -c " + helper.shellQuoted + "); printf '%s' \"${quota_token}\"",
                    timeoutSeconds: 1,
                ),
            ]),
            workingDirectory: nil,
            environment: [:],
            outputLimit: 4_096,
        )
        #expect(result.succeeded == false)
        for name in ["helper", "child"] {
            let value = try String(contentsOfFile: root + "/" + name, encoding: .utf8)
            let pid = try #require(Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)))
            #expect(await TestSupport.poll(timeout: 2) { kill(pid, 0) != 0 })
        }
    }

    @Test
    func `completed reads preserve their output and exit status`() async throws {
        for status in [0, 7] {
            let result = try await FoundationProcessRunner().run(
                [
                    "/bin/zsh", "-fc", SessionService.quotaPayload(
                        "printf quota; printf diagnostic >&2; exit " + String(status),
                        timeoutSeconds: 1,
                    ),
                ],
                workingDirectory: nil,
                environment: [:],
                outputLimit: 4_096,
            )
            #expect(result.status == status)
            #expect(result.standardOutput == "quota")
            #expect(result.standardError == "diagnostic")
        }
    }
}
