import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct ReaderReplyIntegrationTests {
    @Test
    func `opening a Claude reader leaves the Codex index untouched`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let codex = world.paths.sandboxHome + "/.codex/sessions"
        try FileManager.default.createDirectory(atPath: codex, withIntermediateDirectories: true)
        _ = await world.service.liveTranscript(agent: .claudeCode, in: world.repository.path)
        let rollout = codex + "/new.jsonl"
        let metadata = #"{"type":"session_meta","payload":{"cwd":"\#(world.repository.path)","id":"new"}}"#
        try Data(metadata.utf8).write(to: URL(fileURLWithPath: rollout))
        #expect(await world.service.liveTranscript(agent: .codexCLI, in: world.repository.path)?.path == rollout)
    }

    @Test
    func `the last reply can start before the Reader display window`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let directory = try #require(PromptCaptureRunner().transcriptDirectory(
            workingDirectory: world.repository.path,
            sandboxHome: world.paths.sandboxHome,
        ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = URL(fileURLWithPath: directory + "/saved.jsonl")
        let first = #"{"type":"assistant","message":{"content":"first"}}"#
        let ending = String(repeating: "z", count: 20_000)
        let last = #"{"type":"assistant","message":{"content":"\#(ending)"}}"#
        let hidden = String(repeating: "x", count: 8_388_608)
        try Data((first + "\n" + hidden + "\n" + last).utf8).write(to: transcript)
        #expect(await world.service.lastReply(agent: .claudeCode, in: world.repository.path) == "first\n\n" + ending)
    }

    @Test(arguments: ["hello from Reader", "--wait"])
    func `sending from Reader delivers the literal reply and Enter to the selected agent`(_ text: String) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let paneID = try await TestSupport.recordingAgent(client: world.herdr, directory: world.root, activity: "idle")
        try await world.service.reply(#require(ReaderReply(text)), paneID: paneID)
        #expect(await TestSupport.poll {
            (try? String(contentsOfFile: world.root + "/submitted", encoding: .utf8)) ==
                "\u{1B}[200~" + text + "\u{1B}[201~\r"
        })
    }
}
