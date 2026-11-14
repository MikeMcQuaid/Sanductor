@testable import SanductorDomain
import Testing

struct AgentTerminalInputTests {
    @Test
    func `opening a queued question uses Shift Left without submitting`() {
        #expect(AgentKind.codexCLI.answerQuestionInput == [27, 91, 49, 59, 50, 68])
        #expect(AgentKind.claudeCode.answerQuestionInput.isEmpty)
    }

    @Test
    func `queue and immediate input use each agents distinct bindings`() {
        #expect(AgentKind.codexCLI.queueInput == [9])
        #expect(AgentKind.claudeCode.queueInput == [13])
        #expect(AgentKind.codexCLI.sendInputNow == [13])
        #expect(AgentKind.claudeCode.sendInputNow == [24, 19])
    }
}
