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
}
