@testable import SanductorDomain
import Testing

struct AgentTerminalInputTests {
    @Test
    func `queue and immediate input use each agents distinct bindings`() {
        #expect(AgentKind.codexCLI.queueInput == [9])
        #expect(AgentKind.claudeCode.queueInput == [13])
        #expect(AgentKind.codexCLI.sendInputNow == [13])
        #expect(AgentKind.claudeCode.sendInputNow == [24, 19])
    }
}
