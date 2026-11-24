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
        #expect(await tail.omitsEarlierRecords == false)

        try Self.append(String(reply.dropFirst(20)), to: transcript)
        #expect(await tail.entries().map(\.text) == ["hi", "hello"])
        #expect(await tail.entries().map(\.id) == [0, 1])
    }

    @Test
    func `the Mac opens recent records and bounds a growing conversation`() async throws {
        let directory = try TestSupport.temporaryDirectory("tail-window")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/live.jsonl")
        let prompt = #"{"type":"user","message":{"content":"hello"}}"# + "\n"
        try Data((prompt + String(repeating: "x", count: 8_388_608) + "\n" + prompt).utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        #expect(await tail.entries().count == 1)
        #expect(await tail.omitsEarlierRecords)
        try Self.append(String(repeating: prompt, count: 4_100), to: transcript)
        let entries = await tail.entries()
        #expect(entries.count == 4_000)
        #expect(entries.first?.id == 101)
        #expect(entries.last?.id == 4_100)
    }

    @Test
    func `a saved transcript keeps the last record without a newline at the exact window boundary`() async throws {
        let directory = try TestSupport.temporaryDirectory("saved-tail")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/saved.jsonl")
        let prompt = #"{"type":"user","message":{"content":"café"}}"#
        let padding = String(repeating: "x", count: 8_388_608 - 2 * prompt.utf8.count - 2)
        try Data(("older\n" + prompt + "\n" + padding + "\n" + prompt).utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        #expect(await tail.entries(includingFinalLine: true).map(\.text) == ["café", "café"])
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
