@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension SessionNavigationTests {
    @Test(arguments: AgentKind.allCases, [false, true])
    func `model catalogue fixtures recognise direct and sandboxed version probes`(
        agent: AgentKind, sandboxed: Bool,
    ) async {
        let runner = ModelCatalogueRunner()
        let arguments = sandboxed ? SandvaultLauncher(hostUser: "test").command(
            payload: agent.rawValue + " --version </dev/null",
            initialDirectory: "/workspace",
            sessionID: "version-probe",
            sessionName: "sanductor-version",
        ) : [agent.rawValue, "--version"]
        for version in ["1.0", "2.0"] {
            let result = await runner.run(arguments, workingDirectory: nil, environment: [:], outputLimit: nil)
            #expect(result.standardOutput == version)
            #expect(await runner.listings == 0)
            await runner.upgrade(failing: false)
        }
    }

    @Test
    func `model catalogues refresh after upgrades and survive failed refreshes`() async {
        let runner = ModelCatalogueRunner()
        let fixture = Fixture(runner: runner, agents: [ClaudeCodeRunner(), CodexRunner()])
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        #expect(fixture.model.launchChoices(for: .codexCLI).models.isEmpty)
        #expect(fixture.model.launchChoices(for: .claudeCode).models.isEmpty)
        await fixture.model.discoverModels()
        await fixture.model.discoverModels()
        #expect(await runner.listings == 2)
        #expect(fixture.model.launchChoices(for: .claudeCode).names["fable"] == "Fable 5.1")

        await runner.upgrade(failing: true)
        await fixture.model.discoverModels()
        #expect(fixture.model.launchChoices(for: .claudeCode).names["fable"] == "Fable 5.1")
        await runner.upgrade(failing: false)
        await fixture.model.discoverModels()
        #expect(fixture.model.launchChoices(for: .claudeCode).names["fable"] == "Fable 5.2")
        #expect(fixture.model.service.modelNames(for: .claudeCode)["fable"] == "Fable 5.2")
        fixture.model.discoveredModels = [:]
        fixture.model.modelCatalogues = [:]
        fixture.model.restoreDiscoveredModels()
        #expect(fixture.model.launchChoices(for: .codexCLI).modelEfforts["gpt-6-sol"] == ["ultra", "max"])
    }

    @Test
    func `failed model discovery retries once and then reports once`() async {
        let reason = UUID().uuidString
        let runner = ModelCatalogueRunner()
        await runner.upgrade(failing: true, reason: reason)
        let fixture = Fixture(runner: runner, agents: [ClaudeCodeRunner(), CodexRunner()])
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        let reports = { ErrorLog.shared.entries.filter { $0.message.contains(reason) }.map(\.message) }
        await fixture.model.discoverModels()
        #expect(await runner.listings == 4)
        #expect(reports().count == 2)
        #expect(reports().contains { $0.hasPrefix("Codex model discovery") })
        await fixture.model.discoverModels()
        #expect(await runner.listings == 6)
        #expect(reports().count == 2)
    }

    @Test
    func `a failed version probe keeps the last version rather than the cache time`() async throws {
        let runner = ModelCatalogueRunner()
        let fixture = Fixture(runner: runner, agents: [ClaudeCodeRunner(), CodexRunner()])
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        await fixture.model.discoverModels()
        #expect(fixture.model.launchChoices(for: .codexCLI).version == "1.0")
        let codexHome = fixture.root + "/home/.codex"
        try FileManager.default.createDirectory(atPath: codexHome, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(filePath: codexHome + "/models_cache.json"))
        await runner.failVersionProbe()
        await fixture.model.discoverModels()
        #expect(fixture.model.launchChoices(for: .codexCLI).version == "1.0")
    }
}

// MARK: - ModelCatalogueRunner

private actor ModelCatalogueRunner: ProcessRunner {
    // MARK: Internal

    private(set) var listings = 0

    func failVersionProbe() {
        version = ""
    }

    func upgrade(failing: Bool, reason: String = "") {
        version = "2.0"
        self.failing = failing
        self.reason = reason
    }

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        if arguments.contains(where: { $0.contains("--version") }) {
            return ProcessResult(status: 0, standardOutput: version, standardError: "")
        }
        listings += 1
        let output: String
        if arguments.joined().contains("control_request") {
            let name = version == "1.0" ? "Fable 5.1" : "Fable 5.2"
            output = #"{"type":"control_response","response":{"subtype":"success","response":{"models":["#
                + #"{"value":"fable","displayName":""#
                + name + #""}]}}}"#
        } else {
            output = #"{"result":{"data":[{"model":"gpt-6-sol","hidden":false,"supportedReasoningEfforts":["#
                + #"{"reasoningEffort":"max"},{"reasoningEffort":"ultra"}]}]}}"#
        }
        return ProcessResult(status: failing ? 1 : 0, standardOutput: output, standardError: failing ? reason : "")
    }

    // MARK: Private

    private var version = "1.0"
    private var failing = false
    private var reason = ""
}
