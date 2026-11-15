import Foundation
@testable import SanductorData
import Testing

/// Exercises each complete request through the login shell used by the host app.
struct AgentQuotaCommandTests {
    @Test(arguments: ["codex", "claude-file", "claude-keychain"])
    func `complete quota requests survive sudo login escaping`(source: String) async throws {
        let root = try TestSupport.temporaryDirectory("quota-login")
        defer { try? FileManager.default.removeItem(atPath: root) }
        for directory in [".codex", ".claude", "Library/Keychains"] {
            try FileManager.default.createDirectory(atPath: root + "/" + directory, withIntermediateDirectories: true)
        }
        let credentials = #"{"claudeAiOauth":{"accessToken":"test-claude-token"}}"#
        try credentials.write(toFile: root + "/.claude/.credentials.json", atomically: true, encoding: .utf8)
        try #"{"tokens":{"access_token":"test-codex-token","account_id":"test-account"}}"#
            .write(toFile: root + "/.codex/auth.json", atomically: true, encoding: .utf8)
        if source == "claude-keychain" {
            try "".write(toFile: root + "/Library/Keychains/sandvault.keychain-db", atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: root + "/.claude/.credentials.json")
        }
        let adapter: any AgentRunner = source == "codex" ? CodexRunner() : ClaudeCodeRunner()
        let payload = try #require(adapter.quotaCommand)
            .replacing("${HOME}", with: root)
            .replacing("/usr/bin/security", with: "quota_security")
            .replacing("/usr/bin/curl", with: "quota_curl")
        let command = "quota_security() { [[ \"${1}\" == unlock-keychain ]] && return 0; printf '%s' "
            + credentials.shellQuoted + "; }; quota_curl() { /bin/cat > " + (root + "/headers").shellQuoted
            + "; printf '%s' '{\"quota\":true}'; }; " + payload
        let result = try await FoundationProcessRunner().run(
            TestSupport.sudoLoginArguments(["/bin/zsh", "-fc", SessionService.quotaPayload(command)]),
            workingDirectory: nil,
            environment: [:],
        )
        #expect(result.succeeded, Comment(rawValue: result.standardError))
        #expect(result.standardOutput == #"{"quota":true}"#)
        let headers = try String(contentsOfFile: root + "/headers", encoding: .utf8)
        #expect(headers.contains(source == "codex" ? "test-codex-token" : "test-claude-token"))
        #expect(result.standardOutput.contains("token") == false)
        #expect(result.standardError.contains("token") == false)
    }
}
