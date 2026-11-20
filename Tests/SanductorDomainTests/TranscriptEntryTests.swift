import SanductorDomain
import Testing

struct TranscriptEntryTests {
    @Test
    func `the last reply is the agent's last unbroken run of prose`() {
        let roles: [TranscriptEntry.Role] = [.user, .assistant, .tool, .assistant, .assistant, .user]
        let texts = ["do it", "Looking.", "Read: a.swift", "first", "second", "thanks"]
        let entries = zip(roles, texts).enumerated().map { TranscriptEntry(id: $0, role: $1.0, text: $1.1) }
        #expect(entries.lastReply == "first\n\nsecond")
        #expect(Array(entries.prefix(2)).lastReply == "Looking.")
        #expect(Array(entries.prefix(1)).lastReply == nil)
    }
}
