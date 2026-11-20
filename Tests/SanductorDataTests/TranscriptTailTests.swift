import Foundation
import SanductorData
import Testing

/// Follows a transcript as it grows, the way a live session's reader
/// does.
struct TranscriptTailTests {
    // MARK: Internal

    @Test
    func `only whole appended lines are read and each is read once`() async throws {
        let directory = try TestSupport.temporaryDirectory("tail")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/live.jsonl")
        let reply = #"{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}"# + "\n"
        let prompt = #"{"type":"user","promptSource":"typed","message":{"content":"hi"}}"# + "\n"
        // The agent is midway through writing its reply.
        try Data((prompt + reply.prefix(20)).utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        #expect(await tail.entries().map(\.text) == ["hi"])

        try Self.append(String(reply.dropFirst(20)), to: transcript)
        #expect(await tail.entries().map(\.text) == ["hi", "hello"])
        #expect(await tail.entries().map(\.id) == [0, 1])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a write to the transcript rings after the opening ring`() async throws {
        let directory = try TestSupport.temporaryDirectory("tail-changes")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/live.jsonl")
        try Data().write(to: transcript)
        var changes = TranscriptTail(transcript: transcript).changes().makeAsyncIterator()
        await changes.next()

        try Self.append("{}\n", to: transcript)
        await changes.next()
    }

    // MARK: Private

    private static func append(_ text: String, to transcript: URL) throws {
        let handle = try FileHandle(forWritingTo: transcript)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
