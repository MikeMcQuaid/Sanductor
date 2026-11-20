import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct PromptBackfillTests {
    @Test
    func `recover missing prompt IDs from both old lists once and pause recovered jobs`() throws {
        let root = try TestSupport.temporaryDirectory("prompt-backfill")
        let legacy = URL(filePath: root + "/old.json")
        let store = MetadataStore(file: root + "/state.json")
        let domain = "prompt-backfill-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let current = SavedPrompt(name: "Review", prompt: "Current version")
        let missing = SavedPrompt(name: "Fix", prompt: "Earlier text")
        var older = current
        older.prompt = "Older version"
        var job = SavedPrompt(name: "Audit", prompt: "Check dependencies")
        job.schedule = PromptSchedule()
        job.repositoryPath = "/repo"
        try store.updatePersisting { $0.savedPrompts = [current] }
        let encoder = JSONEncoder()
        let data = try JSONSerialization.data(withJSONObject: [
            "savedPrompts": JSONSerialization.jsonObject(with: encoder.encode([older, missing])),
            "scheduledPrompts": JSONSerialization.jsonObject(with: encoder.encode([job])),
            "pullRequestCache": "obsolete",
        ])
        try data.write(to: legacy)
        #expect(try LegacyMigration.backfillPrompts(into: store, from: legacy, defaults: defaults) == 2)
        #expect(store.load().savedPrompts.map(\.prompt) == [current.prompt, missing.prompt, job.prompt])
        #expect(store.load().savedPrompts.last?.isEnabled == false)
        try store.updatePersisting { $0.savedPrompts = [current] }
        #expect(try LegacyMigration.backfillPrompts(into: store, from: legacy, defaults: defaults) == 0)
        #expect(store.load().savedPrompts == [current])
    }
}
