import Foundation
import SanductorData
import SanductorDomain
import Testing

struct PromptMigrationTests {
    @Test
    func `saved text and scheduled jobs migrate together without losing their state`() throws {
        let saved = SavedPrompt(name: "Fix CI", prompt: "Fix these failures")
        var scheduled = SavedPrompt()
        scheduled.repositoryPath = "/repository"
        scheduled.schedule = PromptSchedule()
        scheduled.name = "Review"
        scheduled.prompt = "Review recent work"
        scheduled.isEnabled = false
        scheduled.nextRun = Date(timeIntervalSince1970: 100)
        scheduled.lastRun = Date(timeIntervalSince1970: 50)
        scheduled.lastSession = "previous-run"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let oldFile = try JSONSerialization.data(withJSONObject: [
            "savedPrompts": [["id": saved.id.uuidString, "name": saved.name, "prompt": saved.prompt]],
            "scheduledPrompts": JSONSerialization.jsonObject(with: encoder.encode([scheduled])),
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(AppMetadata.self, from: oldFile)
        #expect(metadata.savedPrompts == [saved, scheduled])
        let rewritten = try encoder.encode(metadata)
        let roundTrip = try decoder.decode(AppMetadata.self, from: rewritten)
        #expect(roundTrip == metadata)
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        #expect(object["scheduledPrompts"] == nil)
    }

    @Test
    func `an already migrated prompt wins over a legacy copy`() throws {
        var scheduled = SavedPrompt()
        scheduled.repositoryPath = "/repository"
        scheduled.schedule = PromptSchedule()
        scheduled.name = "Review"
        scheduled.prompt = "Review recent work"
        var migrated = scheduled
        migrated.schedule = nil
        migrated.repositoryPath = ""
        let encoder = JSONEncoder()
        let file = try JSONSerialization.data(withJSONObject: [
            "savedPrompts": JSONSerialization.jsonObject(with: encoder.encode([migrated])),
            "scheduledPrompts": JSONSerialization.jsonObject(with: encoder.encode([scheduled])),
        ])
        let metadata = try JSONDecoder().decode(AppMetadata.self, from: file)
        #expect(metadata.savedPrompts == [migrated])
    }
}
