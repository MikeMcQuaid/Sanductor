import Foundation
@testable import SanductorRemote
import Testing

struct RecentTranscriptTests {
    @Test
    func `opening publishes just the newest three turns then advances on a real user input`() throws {
        let first = #"{"type":"user","message":{"content":"one"}}"# + "\n"
        let rest = """
        {"type":"user","message":{"content":[{"text":"two"},{"text":"continued"}]}}
        {"type":"assistant","message":{"content":[{"text":"reply"}]}}
        {"type":"user","isMeta":true,"message":{"content":"system"}}
        {"payload":{"type":"user_message","message":"three"}}
        {"payload":{"type":"message","role":"user","content":[{"text":"three"}]}}
        {"payload":{"type":"user_message","message":"four"}}
        """ + "\n"
        var window = RecentTranscript(fileSize: first.utf8.count + rest.utf8.count)
        #expect(try window.append(Data(first.utf8)) == false)
        #expect(try window.append(Data(rest.utf8)))
        #expect(window.entries.map(\.text) == ["two", "continued", "reply", "three", "four"])
        let kept = Array(window.entries.suffix(2))
        #expect(try window.append(Data(#"{"payload":{"type":"user_message","message":"five"}}"#.utf8)) == false)
        #expect(try window.append(Data([10])))
        #expect(window.entries.dropLast() == kept[...])
        #expect(window.entries.last?.text == "five")
        #expect(Set(window.entries.map(\.id)).count == window.entries.count)
    }

    @Test
    func `a long transcript starts near EOF and ignores a split UTF8 record`() throws {
        let reply = #"{"type":"assistant","message":{"content":[{"text":"recent"}]}}"# + "\n"
        var window = RecentTranscript(fileSize: 32 * 1_024 * 1_024)
        let byteCount = 32 * 1_024 * 1_024 - window.offset
        try #require(byteCount <= 256 * 1_024 + 1)
        var bytes = Data(repeating: 0x80, count: byteCount - reply.utf8.count - 1)
        bytes.append(10)
        bytes.append(contentsOf: reply.utf8)
        #expect(try window.append(bytes))
        #expect(window.entries.map(\.text) == ["recent"])
    }

    @Test
    func `a turn with many tool calls keeps only the latest hundred entries`() throws {
        var window = RecentTranscript(fileSize: 0)
        for index in 0 ... 110 {
            let line = #"{"payload":{"type":"function_call","name":"tool\#(index)"}}"# + "\n"
            #expect(try window.append(Data(line.utf8)))
        }
        #expect(window.entries.count == 100)
        #expect(window.entries.first?.text == "tool11")
        #expect(window.entries.last?.id == 110)
    }

    @Test
    func `long replies share a byte budget and an oversized record does not interrupt later replies`() throws {
        var window = RecentTranscript(fileSize: 0)
        for word in ["a", "b"] {
            let text = String(repeating: word, count: 150_000)
            let line = #"{"payload":{"type":"agent_message","message":"\#(text)"}}"# + "\n"
            #expect(try window.append(Data(line.utf8)))
            #expect(window.entries.map(\.text) == [text])
        }
        let oversized = Data(repeating: 65, count: 200_000)
        #expect(try window.append(Data(#"{"payload":{"type":"agent_message","message":""#.utf8) + oversized) == false)
        #expect(try window.append(oversized + Data("\"}}\n".utf8)) == false)
        let next = #"{"payload":{"type":"agent_message","message":"still following"}}"# + "\n"
        #expect(try window.append(Data(next.utf8)))
        #expect(window.entries.last?.text == "still following")
    }
}
