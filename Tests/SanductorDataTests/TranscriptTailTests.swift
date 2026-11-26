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
        try Self.append(String(repeating: prompt, count: 100), to: transcript)
        let entries = await tail.entries()
        #expect(entries.count == 24)
        #expect(entries.first?.id == 77)
        #expect(entries.last?.id == 100)
    }

    @Test
    func `a saved transcript keeps the last record without a newline at the exact window boundary`() async throws {
        let directory = try TestSupport.temporaryDirectory("saved-tail")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/saved.jsonl")
        let prompt = #"{"type":"user","message":{"content":"café"}}"#
        let padding = String(repeating: "x", count: 262_144 - 2 * prompt.utf8.count - 2)
        try Data(("older\n" + prompt + "\n" + padding + "\n" + prompt).utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        #expect(await tail.entries(includingFinalLine: true).map(\.text) == ["café", "café"])
    }

    @Test
    func `a short opening window skips old replies and looks past trailing bookkeeping when needed`() async throws {
        let directory = try TestSupport.temporaryDirectory("reader-bookkeeping")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/log.jsonl")
        let reply = #"{"type":"assistant","message":{"content":"reply"}}"# + "\n"
        let metadata = #"{"type":"system","data":""# + String(repeating: "x", count: 300_000) + #""}"# + "\n"
        try Data((reply + metadata + reply).utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        #expect(await tail.entries().map(\.text) == ["reply"])
        #expect(await tail.omitsEarlierRecords)
        try Self.append(metadata, to: transcript)
        let reopened = TranscriptTail(transcript: transcript)
        #expect(await reopened.entries().last?.text == "reply")
        let before = try #require(await tail.entries().last)
        #expect(before.text == "reply")
        try Self.append(metadata + reply, to: transcript)
        let after = try #require(await tail.entries().last)
        #expect(after.id > before.id)
    }

    @Test
    func `a large final reply keeps its ending and the next entry's identity`() async throws {
        let directory = try TestSupport.temporaryDirectory("reader-text-budget")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let transcript = URL(fileURLWithPath: directory + "/log.jsonl")
        let text = String(repeating: "👩🏽‍💻", count: 2_000) + " final words"
        let reply = #"{"type":"assistant","message":{"content":"\#(text)"}}"# + "\n"
        try Data(reply.utf8).write(to: transcript)
        let tail = TranscriptTail(transcript: transcript)
        let entry = try #require(await tail.entries().last)
        #expect(entry.text.utf8.count <= 16_384)
        #expect(entry.text.hasSuffix(" final words"))
        #expect(text.hasSuffix(entry.text))
        #expect(await tail.omitsEarlierRecords)
        try Self.append(#"{"type":"user","message":{"content":"next"}}"# + "\n", to: transcript)
        let next = await tail.entries()
        #expect(next.map(\.text) == ["next"])
        #expect(next.last?.id == entry.id + 1)
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
