import Foundation
@testable import SanductorData
import Testing

struct AgentQuotaRequestTests {
    @Test(arguments: [
        ("2.1.325 (Claude Code)", String?.some("claude-cli/2.1.325 (external, cli)")),
        ("", nil),
        ("unexpected", nil),
        ("2.1.325\nheader = \"X-Injected: yes\"", nil),
    ])
    func `claude quota uses the installed client identity`(version: String, agent: String?) async throws {
        let root = try TestSupport.temporaryDirectory("claude-quota-request")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let payload = try #require(ClaudeCodeRunner().quotaCommand)
            .replacing("/usr/bin/security", with: "quota_security")
            .replacing("/usr/bin/plutil", with: "quota_token_fixture")
            .replacing("/usr/bin/curl", with: "quota_curl")
        let result = try await TestSupport.run(TestSupport.sudoLoginArguments([
            "/bin/zsh", "-fc",
            "claude() { printf '%s' " + version.shellQuoted + "; return " + (version.isEmpty ? "1" : "0") + "; }; "
                + "quota_security() { return 1; }; "
                + "quota_token_fixture() { printf '%s' 'test-secret'; }; "
                + "quota_curl() { printf '%s\\n' \"${@}\"; /bin/cat > " + (root + "/stdin").shellQuoted
                + "; }; " + payload,
        ]))
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("https://api.anthropic.com/api/oauth/usage?cedar_ember=1"))
        #expect(result.standardOutput.contains("test-secret") == false)
        #expect(result.standardError.contains("test-secret") == false)
        let expected = "header = \"Authorization: Bearer test-secret\"\n"
            + "header = \"anthropic-beta: oauth-2025-04-20\"\n"
            + (agent.map { "header = \"User-Agent: " + $0 + "\"\n" } ?? "")
        #expect(try String(contentsOfFile: root + "/stdin", encoding: .utf8) == expected)
    }
}
