import Foundation
@testable import SanductorData
import Testing

struct PromptSecretTests {
    @Test
    func `substitution reads only complete names and never interprets their values`() async throws {
        let template = "Use $KEY or ${KEY}. Keep $KEY_LONG, $HOME and $(id). Old key: ${old service}."
        let value = "q '$OTHER' \\ &"
        let delivered = try await PromptSecrets.expand(template) { name in
            switch name {
            case "KEY":
                value

            case "old service":
                "old"

            default:
                nil
            }
        }
        #expect(delivered == "Use " + value + " or " + value + ". Keep $KEY_LONG, $HOME and $(id). Old key: old.")
    }

    @Test
    func `fetched GitHub text cannot expand secrets`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        var service = world.service
        service.promptSecret = { $0 == "KEY" ? "fixture" : nil }
        let prompt = try await service.preparePrompt("Use $KEY") { userText in
            GitHubClient.issuePrompt(number: 1, title: "$KEY", body: "Use $KEY", context: userText)
        }
        #expect(prompt.template.contains("fixture") == false)
        #expect(prompt.delivery.contains("issue #1: $KEY\n\nUse $KEY"))
        #expect(prompt.delivery.contains("Additional context from the user:\nUse fixture"))
    }

    @Test
    func `literal credentials pass through without masking or blocking`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let text = "ghp_" + String(repeating: "x", count: 32)
        let prompt = try await world.service.preparePrompt(text)
        #expect(prompt.template == text)
        #expect(prompt.delivery == text)
    }

    @Test
    func `lookup errors stop delivery`() async {
        await #expect(throws: (any Error).self) {
            try await PromptSecrets.expand("Use $KEY") { _ in throw CocoaError(.fileReadNoPermission) }
        }
    }
}
