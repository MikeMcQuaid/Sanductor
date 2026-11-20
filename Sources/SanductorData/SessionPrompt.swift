// MARK: - SessionPrompt

/// Only the agent receives the expanded text. Branch naming, history and retries use the template.
struct SessionPrompt {
    let template: String
    let delivery: String
}

extension SessionService {
    func preparePrompt(
        _ userText: String,
        composing: (String) throws -> String = \.self,
    ) async throws -> SessionPrompt {
        let template = try composing(userText)
        let expanded = try await PromptSecrets.expand(userText, read: promptSecret)
        return try SessionPrompt(template: template, delivery: expanded == userText ? template : composing(expanded))
    }
}
