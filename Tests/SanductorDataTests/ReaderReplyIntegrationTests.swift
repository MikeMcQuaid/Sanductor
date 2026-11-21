import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct ReaderReplyIntegrationTests {
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
