import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct ScheduledSessionIntegrationTests {
    @Test
    func `a scheduled launch reuses its prepared worktree and preserves prompt and options`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        var prompt = SavedPrompt()
        prompt.repositoryPath = world.repository.path
        prompt.schedule = PromptSchedule()
        prompt.name = "Weekly checks"
        prompt.prompt = "Review `changes`, $(without expansion)\nand report findings using $KEY"
        prompt.model = "fable"
        prompt.effort = "max"
        let due = Date(timeIntervalSince1970: 1_893_686_400)
        let prepared = try await world.service.createWorktreePath(
            repository: world.repository, branch: prompt.branch(for: due),
        )
        var service = world.service
        service.promptSecret = { $0 == "KEY" ? "fixture" : nil }
        let name = try await service.launchScheduledPrompt(prompt, due: due)
        #expect(SessionName.isSanductor(name))
        let expected = prompt.prompt.replacing("$KEY", with: "fixture")
        #expect(await TestSupport.poll {
            (try? String(contentsOfFile: prepared + "/agent-prompt.txt", encoding: .utf8)) == expected
        })
        #expect(try String(contentsOfFile: prepared + "/agent-arguments.txt", encoding: .utf8)
            == "--model fable --effort max")
        #expect(try await world.service.git.worktrees(of: world.repository).map(\.path) == [prepared])
        #expect(service.store.load().prompts[name] == prompt.prompt)
        #expect(world.service.store.load().sessionsByWorktree[prepared] == name)
    }

    @Test
    func `schedules round trip through disk without losing older metadata`() throws {
        var metadata = AppMetadata()
        metadata.prompts["existing"] = "keep"
        var prompt = SavedPrompt()
        prompt.repositoryPath = "/repository"
        prompt.schedule = PromptSchedule()
        prompt.name = "Monthly review"
        prompt.prompt = "Review the project"
        prompt.schedule?.frequency = .monthly
        prompt.schedule?.day = 31
        prompt.nextRun = Date(timeIntervalSince1970: 1_893_686_400)
        metadata.savedPrompts = [prompt]
        let root = try TestSupport.temporaryDirectory("schedule-round-trip")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/state.json"
        try MetadataStore(file: file).updatePersisting { $0 = metadata }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(AppMetadata.self, from: Data(contentsOf: URL(filePath: file)))
        #expect(loaded.savedPrompts == [prompt])
        #expect(loaded.prompts["existing"] == "keep")
        let old = try JSONDecoder().decode(AppMetadata.self, from: Data(#"{"prompts":{"existing":"keep"}}"#.utf8))
        #expect(old.savedPrompts.isEmpty)
        #expect(old.prompts["existing"] == "keep")
    }
}
