import Foundation
@testable import SanductorData
import Testing

/// Pins the account responses independently of the changing live services.
struct AgentQuotaTests {
    @Test
    func `claude's structured limits include total and Fable without double counting legacy fields`() throws {
        let quotas = try ClaudeCodeRunner().parseQuota(Data(#"""
        {
          "seven_day": {"utilization": 51, "resets_at": "2026-11-18T03:59:59Z"},
          "limits": [
            {"kind":"weekly_all","group":"weekly","percent":51,
             "resets_at":"2026-11-18T03:59:59.647363+00:00","scope":null},
            {"kind":"weekly_scoped","group":"weekly","percent":100,
             "resets_at":"2026-11-18T03:59:59Z",
             "scope":{"model":{"id":null,"display_name":"Fable"}}}
          ]
        }
        """#.utf8))
        #expect(quotas.map(\.label) == ["Weekly", "Weekly"])
        #expect(quotas.map(\.modelName) == [nil, "Fable"])
        #expect(quotas.map(\.usedPercent) == [51, 100])
        #expect(quotas.allSatisfy { $0.resetsAt != nil })
        #expect(Set(quotas.map(\.id)).count == 2)
    }

    @Test
    func `older Claude responses retain real zeroes and omit absent allowances`() throws {
        let quotas = try ClaudeCodeRunner().parseQuota(Data(#"""
        {
          "five_hour": {"utilization":0,"resets_at":null},
          "seven_day": {"utilization":22.5,"resets_at":"invalid"},
          "seven_day_overage_included": {"utilization":75,"resets_at":null},
          "seven_day_opus": null
        }
        """#.utf8))
        #expect(quotas.map(\.usedPercent) == [0, 22.5, 75])
        #expect(quotas.map(\.label) == ["5 hours", "Weekly", "Weekly"])
        #expect(quotas.map(\.modelName) == [nil, nil, "Fable"])
        #expect(quotas.allSatisfy { $0.resetsAt == nil })
    }

    @Test
    func `a weekly-only Codex primary is labelled by duration`() throws {
        let quotas = try CodexRunner().parseQuota(Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":604800,
          "reset_at":1794992259},"secondary_window":null}}
        """#.utf8))
        #expect(quotas.count == 1)
        #expect(quotas.first?.label == "Weekly")
        #expect(quotas.first?.usedPercent == 50)
        #expect(quotas.first?.resetsAt == Date(timeIntervalSince1970: 1_794_992_259))
    }

    @Test
    func `codex keeps both windows and percentages over the allowance`() throws {
        let quotas = try CodexRunner().parseQuota(Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000},
          "secondary_window":{"used_percent":101,"limit_window_seconds":604800}}}
        """#.utf8))
        #expect(quotas.map(\.label) == ["5 hours", "Weekly"])
        #expect(quotas.map(\.usedPercent) == [0, 101])
    }

    @Test
    func `missing quota is never reported as unused`() throws {
        #expect(try CodexRunner().parseQuota(Data(#"{"rate_limit":null}"#.utf8)).isEmpty)
        #expect(try ClaudeCodeRunner().parseQuota(Data(#"{"limits":[],"seven_day":null}"#.utf8)).isEmpty)
        #expect(throws: (any Error).self) { try CodexRunner().parseQuota(Data("not JSON".utf8)) }
        #expect(throws: (any Error).self) { try ClaudeCodeRunner().parseQuota(Data("not JSON".utf8)) }
    }

    @Test
    func `a plan without Fable reports only overall usage`() throws {
        let quotas = try ClaudeCodeRunner().parseQuota(Data(#"""
        {"seven_day":{"utilization":25},"seven_day_overage_included":null,
         "limits":[{"kind":"weekly_all","group":"weekly","percent":25,"scope":null}]}
        """#.utf8))
        #expect(quotas.count == 1)
        #expect(quotas.first?.modelName == nil)
        #expect(quotas.first?.usedPercent == 25)
    }

    @Test
    func `quota tokens stay on curl stdin through sudo's login shell`() async throws {
        let root = try TestSupport.temporaryDirectory("quota-command")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let token = "test-secret_token.123"
        let payload = "quota_token=" + token.shellQuoted + "; " + CodexRunner()
            .quotaRequest(
                url: "https://example.invalid/usage",
            )
            .replacing("/usr/bin/curl", with: "quota_curl")
        let result = try await TestSupport.run(TestSupport.sudoLoginArguments([
            "/bin/zsh", "-fc",
            "quota_curl() { printf '%s\\n' \"${@}\"; /bin/cat > " + (root + "/stdin").shellQuoted
                + "; }; " + payload,
        ]))
        #expect(result.standardOutput.contains(token) == false)
        #expect(result.standardError.contains(token) == false)
        #expect(result.standardOutput.contains("--config\n-"))
        #expect(try String(contentsOfFile: root + "/stdin", encoding: .utf8)
            == "header = \"Authorization: Bearer " + token + "\"\n")
    }

    @Test(arguments: ["", "bad\nheader", "bad\"header"])
    func `invalid credentials cannot inject curl configuration`(token: String) async throws {
        let result = try await FoundationProcessRunner().run(
            [
                "/bin/zsh", "-fc", "quota_token=" + token.shellQuoted + "; "
                    + CodexRunner()
                    .quotaRequest(url: "https://example.invalid/usage")
                    .replacing("/usr/bin/curl", with: "echo should-not-run"),
            ],
            workingDirectory: nil,
            environment: [:],
        )
        #expect(result.succeeded == false)
        #expect(result.standardOutput.isEmpty)
    }
}
