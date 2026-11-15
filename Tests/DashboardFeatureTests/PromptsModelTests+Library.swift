@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

extension PromptsModelTests {
    @Test
    func `saved prompts survive editing and decoding alongside schedules`() throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let model = makeModel(fixture)
        #expect(model.save(prompt()))
        let schedules = model.prompts
        var reusable = SavedPrompt(name: "Fix CI", prompt: "Look at the last commit and fix these CI failures:")
        #expect(model.save(reusable))
        reusable.prompt += "\nKeep the change small."
        #expect(model.save(reusable))
        #expect(model.prompts == schedules + [reusable])
        #expect(model.save(SavedPrompt(name: "Empty", prompt: " \n")) == false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(
            AppMetadata.self, from: Data(contentsOf: URL(filePath: fixture.root + "/state.json")),
        )
        #expect(persisted.savedPrompts == model.prompts)
        #expect(try decoder.decode(AppMetadata.self, from: Data("{}".utf8)).savedPrompts.isEmpty)
        #expect(makeModel(fixture).prompts == model.prompts)
        model.delete(reusable)
        #expect(model.prompts == schedules)
        #expect(fixture.model.store.load().savedPrompts == schedules)
    }

    @Test
    func `prompt choices share one sorted library and include this repository's paused schedules`() {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let model = makeModel(fixture)
        let reusable = SavedPrompt(name: "Fix CI", prompt: "Reusable everywhere")
        var here = prompt()
        here.repositoryPath = fixture.repository.path
        here.isEnabled = false
        var elsewhere = prompt()
        elsewhere.repositoryPath = "/other"
        #expect(model.save(here))
        #expect(model.save(elsewhere))
        #expect(model.save(reusable))
        #expect(model.availablePrompts(repositoryPath: fixture.repository.path).map(\.id) == [here.id, reusable.id])
        here.prompt = "Edited schedule text"
        #expect(model.save(here))
        #expect(model.availablePrompts(repositoryPath: fixture.repository.path).first?.prompt == here.prompt)
        #expect(model.availablePrompts(repositoryPath: nil) == [reusable])
        #expect(model.prompts.allSatisfy { $0.lastRun == nil })
    }

    @Test
    func `a failed save keeps the previous prompt list and reports the failure`() throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let blocked = fixture.root + "/not-a-directory"
        try Data("file".utf8).write(to: URL(filePath: blocked))
        let model = PromptsModel(store: MetadataStore(file: blocked + "/state.json"), service: fixture.model.service)
        #expect(model.save(SavedPrompt(name: "Keep", prompt: "My draft")) == false)
        #expect(model.prompts.isEmpty)
        #expect(model.error != nil)
    }

    @Test
    func `removing and adding a schedule keeps the prompt identity and launch history`() async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        let original = prompt()
        fixture.model.store.update { $0.savedPrompts = [original] }
        let model = makeModel(fixture)
        model.launch = { _, _ in "previous-run" }
        await model.runDue()
        var edited = try #require(model.prompts.first)
        let lastRun = edited.lastRun
        edited.schedule = nil
        #expect(model.save(edited))
        let plain = try #require(model.prompts.first)
        #expect(plain.id == original.id)
        #expect(plain.prompt == original.prompt)
        #expect(plain.lastSession == "previous-run")
        #expect(plain.lastRun == lastRun)
        #expect(plain.nextRun == nil)
        #expect(plain.repositoryPath.isEmpty)
        #expect(model.availablePrompts(repositoryPath: "/elsewhere") == [plain])
        edited = plain
        edited.schedule = PromptSchedule()
        #expect(model.save(edited) == false)
        edited.repositoryPath = "/another-repository"
        #expect(model.save(edited))
        #expect(model.prompts.count == 1)
        #expect(model.prompts.first?.id == original.id)
        #expect(model.prompts.first?.lastSession == "previous-run")
        #expect(try #require(model.prompts.first?.nextRun) > model.now())
    }

    @Test
    func `plain text never launches even with a leftover due date`() async {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var reusable = SavedPrompt(name: "Fix CI", prompt: "Do not run without a schedule")
        reusable.nextRun = .distantPast
        reusable.repositoryPath = "/repository"
        fixture.model.store.update { $0.savedPrompts = [reusable] }
        let model = makeModel(fixture)
        model.launch = { _, _ in
            Issue.record("Only scheduled prompts can launch")
            return "unexpected"
        }
        await model.runDue()
        await model.start(reusable)
        #expect(model.prompts.first?.lastRun == nil)
        #expect(model.save(reusable))
        #expect(model.prompts.first?.nextRun == nil)
    }

    @Test
    func `moving an overdue prompt to another repository starts its schedule afresh`() throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var edited = prompt()
        fixture.model.store.update { $0.savedPrompts = [edited] }
        let model = makeModel(fixture)
        edited.repositoryPath = "/another-repository"
        #expect(model.save(edited))
        #expect(try #require(model.prompts.first?.nextRun) > model.now())
    }
}
