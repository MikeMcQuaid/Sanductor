import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension SessionServiceIntegrationTests {
    @Test
    func `invalid saved model choices fail before creating a worktree`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        await #expect(throws: SessionServiceError.self) {
            try await world.service.createSession(
                repository: world.repository,
                prompt: "Invalid effort",
                agent: .claudeCode,
                options: AgentLaunchOptions(model: "fable", effort: "ultra"),
            )
        }
        #expect(FileManager.default.fileExists(atPath: world.paths.worktreesDirectory) == false)
    }

    @Test
    func `undiscovered models start on the CLI's own defaults`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let options = try world.service.validate(AgentLaunchOptions(model: "gpt-6-sol", effort: "max"), for: .codexCLI)
        #expect(options.model == nil)
        #expect(options.effort == nil)
    }
}
