import SanductorDomain
import Testing

struct ReaderReplyTests {
    @Test(arguments: ["", "  ", "one\ntwo", "one\rtwo", "a\u{2028}b", "a\u{1B}b", String(repeating: "é", count: 501)])
    func `a reply must be one short printable line`(_ input: String) {
        #expect(ReaderReply(input) == nil)
    }

    @Test
    func `a reply is one literal argument even if it starts like an option`() throws {
        let reply = try #require(ReaderReply("--wait; $(echo 'héllo')"))
        #expect(reply.arguments(paneID: "pane") == ["agent", "prompt", "pane", "--wait; $(echo 'héllo')"])
    }

    @Test(arguments: [
        "", #"{"result":{"type":"ok","agent":{"pane_id":"pane"}}}"#,
        #"{"result":{"type":"agent_prompted","agent":{"pane_id":"another-pane"}}}"#,
    ])
    func `only confirmation from the selected agent clears the reply`(_ output: String) {
        #expect(ReaderReply.wasSubmitted(output, to: "pane") == false)
    }
}
