import Foundation
@testable import SanductorData
import Testing

struct AgentRetentionTests {
    @Test
    func `adapters attribute recovery files without including credentials or following links`() throws {
        let root = try TestSupport.temporaryDirectory("agent-retention")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fixtures = [
            ".codex/sessions/date/old.jsonl": #"{"type":"session_meta","payload":{"cwd":"/old"}}"#,
            ".codex/archived_sessions/unknown.jsonl": "broken",
            ".claude/projects/project/session.jsonl": #"{"cwd":"/tree","sessionId":"session"}"#,
            ".claude/file-history/session/copy": "old file",
            ".claude/paste-cache/paste.txt": "old paste",
            ".codex/auth.json": "credentials",
            ".claude/settings.json": "settings",
        ]
        let manager = FileManager.default
        for (path, text) in fixtures {
            let url = URL(filePath: root + "/" + path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try manager.createSymbolicLink(
            atPath: root + "/.codex/sessions/link", withDestinationPath: root + "/.claude",
        )
        let codex = CodexRunner().conversationFiles(sandboxHome: root)
        #expect(codex == [
            root + "/.codex/sessions/date/old.jsonl": "/old",
            root + "/.codex/archived_sessions/unknown.jsonl": "",
        ])
        let claude = ClaudeCodeRunner().conversationFiles(sandboxHome: root)
        #expect(claude == [
            root + "/.claude/projects/project/session.jsonl": "/tree",
            root + "/.claude/file-history/session/copy": "/tree",
            root + "/.claude/paste-cache/paste.txt": "",
        ])
    }
}
