import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
@testable import TerminalUI
import Testing

/// Tab switches and failures must not turn an occasional read into frequent polling.
@MainActor
struct AgentQuotaModelTests {
    // MARK: Internal

    @Test
    func `shared resets combine model usage without hiding other periods or unknown resets`() {
        let reading = AgentQuotaModel.Reading(quotas: [
            AgentQuota(
                id: "weekly",
                label: "Weekly",
                usedPercent: 51,
                resetsAt: Date(timeIntervalSince1970: 1_000.1),
            ),
            AgentQuota(
                id: "fable",
                label: "Weekly",
                usedPercent: 100,
                resetsAt: Date(timeIntervalSince1970: 1_000.9),
                modelName: "Fable",
            ),
            AgentQuota(
                id: "session",
                label: "5 hours",
                usedPercent: 10,
                resetsAt: Date(timeIntervalSince1970: 1_000.1),
            ),
            AgentQuota(
                id: "opus",
                label: "Weekly",
                usedPercent: 20,
                resetsAt: Date(timeIntervalSince1970: 2_000),
                modelName: "Opus",
            ),
            AgentQuota(id: "unknown", label: "Weekly", usedPercent: 30, resetsAt: nil),
        ])
        #expect(reading.quotaGroups.map { $0.map(\.id) } == [
            ["weekly", "fable"], ["session"], ["opus"], ["unknown"],
        ])
    }

    @Test
    func `reopening the pane is throttled and a failed refresh preserves each last reading`() async {
        let calls = Mutex(0)
        let failing = Mutex(false)
        let model = AgentQuotaModel { _ in
            calls.withLock { $0 += 1 }
            if failing.withLock({ $0 }) {
                throw Failure.unavailable
            }
            return [AgentQuota(id: "weekly", label: "Weekly", usedPercent: 50, resetsAt: nil)]
        }
        let start = Date(timeIntervalSince1970: 1_000)
        await model.refresh(now: start)
        await model.refresh(now: start.addingTimeInterval(599))
        #expect(calls.withLock { $0 } == 2)
        #expect(model.readings[.claudeCode]?.quotas.first?.usedPercent == 50)

        failing.withLock { $0 = true }
        await model.refresh(now: start.addingTimeInterval(600))
        await model.refresh(now: start.addingTimeInterval(601))
        #expect(calls.withLock { $0 } == 4)
        #expect(model.readings[.claudeCode]?.quotas.first?.usedPercent == 50)
        #expect(model.readings[.claudeCode]?.updatedAt == start)
        #expect(model.readings[.codexCLI]?.isUnavailable == true)

        failing.withLock { $0 = false }
        await model.refresh(now: start.addingTimeInterval(1_200))
        #expect(model.readings[.codexCLI]?.isUnavailable == false)
        #expect(model.readings[.codexCLI]?.updatedAt == start.addingTimeInterval(1_200))
    }

    @Test
    func `one unavailable provider does not hide the other or fabricate a zero`() async {
        let model = AgentQuotaModel { agent in
            if agent == .claudeCode {
                throw Failure.unavailable
            }
            return [AgentQuota(id: "weekly", label: "Weekly", usedPercent: 0, resetsAt: nil)]
        }
        await model.refresh()
        #expect(model.readings[.claudeCode]?.quotas.isEmpty == true)
        #expect(model.readings[.claudeCode]?.updatedAt == nil)
        #expect(model.readings[.claudeCode]?.isUnavailable == true)
        #expect(model.readings[.codexCLI]?.quotas.first?.usedPercent == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a quota deadline preserves stale usage and releases the next refresh`() async {
        let calls = Mutex<[AgentKind: Int]>([:])
        let model = AgentQuotaModel { agent in
            let attempt = calls.withLock { calls in
                calls[agent, default: 0] += 1
                return calls[agent, default: 0]
            }
            if agent == .claudeCode, attempt == 2 {
                let result = try await FoundationProcessRunner().run(
                    ["/bin/zsh", "-fc", SessionService.quotaPayload("/bin/sleep 3", timeoutSeconds: 1)],
                    workingDirectory: nil,
                    environment: [:],
                    outputLimit: 4_096,
                )
                guard result.succeeded else {
                    throw Failure.unavailable
                }
            }
            return [AgentQuota(id: "weekly", label: "Weekly", usedPercent: Double(attempt), resetsAt: nil)]
        }
        let start = Date(timeIntervalSince1970: 1_000)
        await model.refresh(now: start)
        await model.refresh(now: start.addingTimeInterval(600))
        #expect(model.readings[.claudeCode]?.isUnavailable == true)
        #expect(model.readings[.claudeCode]?.quotas.first?.usedPercent == 1)
        #expect(model.readings[.codexCLI]?.quotas.first?.usedPercent == 2)

        await model.refresh(now: start.addingTimeInterval(1_200))
        #expect(model.readings[.claudeCode]?.isUnavailable == false)
        #expect(model.readings[.claudeCode]?.quotas.first?.usedPercent == 3)
        #expect(model.readings[.codexCLI]?.quotas.first?.usedPercent == 3)
    }

    // MARK: Private

    private enum Failure: Error {
        case unavailable
    }
}
