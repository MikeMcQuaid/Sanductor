import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct AgentOutputLinkTests {
    @Test(arguments: ["four po**se**s", "four po&#115;es"])
    func `a formatted word preserves every destination for its rendered label`(spelling: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let transcript = URL(filePath: world.root).appending(path: "test.jsonl")
        let plain = #"{"type":"assistant","message":{"content":"[four poses](a.jpg)"}}"#
        let styled = #"{"message":{"content":"[\#(spelling)](b.jpg)"},"type":"assistant"}"#
        try styled.write(to: transcript, atomically: true, encoding: .utf8)
        #expect(await world.service.linkDestination(label: "four poses", transcript: transcript)?.path == "b.jpg")
        try (plain + "\n" + styled).write(to: transcript, atomically: true, encoding: .utf8)
        #expect(await world.service.linkDestination(label: "four poses", transcript: transcript) == nil)
    }

    @Test
    func `ordinary mentions of a short label do not hide its link in a large transcript`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let transcript = URL(filePath: world.root).appending(path: "test.jsonl")
        let output = String(repeating: "click here ", count: 800_000)
        let tool = #"{"type":"tool","text":"\#(output)"}"#
        let reply = #"{"type":"assistant","message":{"content":[{"type":"text","text":"[here](https://x.test)"}]}}"#
        try (tool + "\n" + reply).write(to: transcript, atomically: true, encoding: .utf8)
        #expect(await world.service.linkDestination(label: "here", transcript: transcript)?.host == "x.test")
    }

    @Test(arguments: AgentKind.allCases)
    func `a labelled image in an agent reply resolves to a private preview copy`(agent: AgentKind) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let image = URL(filePath: world.repository.path).appending(path: "four poses.jpg")
        try Data("fixture".utf8).write(to: image)
        let label = "four poses side by side"
        let link = "[**four poses** side by side](four%20poses.jpg)"
        let record =
            switch agent {
            case .codexCLI:
                #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":["#
                    + #"{"type":"output_text","text":"\#(link)"}]}}"#

            case .claudeCode:
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(link)"}]}}"#
            }
        let transcript = URL(filePath: world.root).appending(path: "test.jsonl")
        try (record + "\n").write(to: transcript, atomically: true, encoding: .utf8)
        let destination = try #require(await world.service.linkDestination(label: label, transcript: transcript))
        let preview = try await world.service.previewFile(destination, in: world.repository.path)
        defer { try? FileManager.default.removeItem(at: preview.deletingLastPathComponent()) }
        #expect(preview.lastPathComponent == image.lastPathComponent)
        #expect(preview != image)
        #expect(try Data(contentsOf: preview) == Data("fixture".utf8))
        try (record + "\n" + record.replacing("four%20poses.jpg", with: "other.jpg"))
            .write(to: transcript, atomically: true, encoding: .utf8)
        #expect(await world.service.linkDestination(label: label, transcript: transcript) == nil)
        let outside = URL(filePath: world.root).appending(path: "outside")
        try Data().write(to: outside)
        let alias = URL(filePath: world.repository.path).appending(path: "outside.jpg")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let remote = try #require(URL(string: "file://other/file"))
        for rejected in [outside, alias, URL(filePath: world.repository.path), remote] {
            await #expect(throws: (any Error).self) {
                _ = try await world.service.previewFile(rejected, in: world.repository.path)
            }
        }
    }
}
