import Foundation
@testable import SessionFeature
import Testing

@MainActor
struct SessionReaderModelTests {
    @Test(.timeLimit(.minutes(1)))
    func `the reader follows its transcript as the agent writes`() async throws {
        let transcript = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("sanductor-reader-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        try Data((#"{"type":"user","promptSource":"typed","message":{"content":"hi"}}"# + "\n").utf8)
            .write(to: transcript)
        let model = SessionReaderModel { transcript }
        #expect(model.hasLoaded == false)
        let following = Task {
            await model.follow()
        }
        defer { following.cancel() }
        while model.entries.map(\.text) != ["hi"] {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.hasLoaded)

        let handle = try FileHandle(forWritingTo: transcript)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            (#"{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}"# + "\n").utf8,
        ))
        while model.entries.map(\.text) != ["hi", "hello"] {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a cancelled follow leaves a newer one's log alone`() async throws {
        let transcript = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("sanductor-reader-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        try Data((#"{"type":"user","promptSource":"typed","message":{"content":"hi"}}"# + "\n").utf8)
            .write(to: transcript)
        // The first lookup answers late, after the follow that
        // replaced it has shown its log.
        var held: CheckedContinuation<Void, Never>?
        var lookups = 0
        let model = SessionReaderModel {
            lookups += 1
            guard lookups == 1 else {
                return transcript
            }

            await withCheckedContinuation { held = $0 }
            return nil
        }
        let stale = Task {
            await model.follow()
        }
        while held == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        stale.cancel()
        let current = Task {
            await model.follow()
        }
        defer { current.cancel() }
        while model.entries.map(\.text) != ["hi"] {
            try await Task.sleep(for: .milliseconds(10))
        }
        held?.resume()
        await stale.value
        #expect(model.entries.map(\.text) == ["hi"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a transcript written after the reader opened is found`() async throws {
        let transcript = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("sanductor-reader-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        var isWritten = false
        let model = SessionReaderModel(discovery: .milliseconds(10)) { isWritten ? transcript : nil }
        let following = Task {
            await model.follow()
        }
        defer { following.cancel() }
        // Empty rather than loading: there is nothing yet to wait on.
        while model.hasLoaded == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.entries.isEmpty)

        try Data((#"{"type":"user","promptSource":"typed","message":{"content":"hi"}}"# + "\n").utf8)
            .write(to: transcript)
        isWritten = true
        while model.entries.map(\.text) != ["hi"] {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
