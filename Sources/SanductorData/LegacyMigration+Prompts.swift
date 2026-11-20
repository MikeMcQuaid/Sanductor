import Foundation
import SanductorDomain

public extension LegacyMigration {
    /// Whether startup still needs to inspect the historical prompt library.
    static func needsPromptBackfill(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: promptBackfillKey) == false
    }

    /// The old file copy could skip the whole prompt library when both apps already had metadata.
    @discardableResult
    static func backfillPrompts(
        into store: MetadataStore,
        from file: URL = URL(filePath: NSHomeDirectory() + "/Library/Application Support/AgentIDE/state.json"),
        defaults: UserDefaults = .standard,
    ) throws -> Int {
        guard needsPromptBackfill(defaults: defaults) else {
            return 0
        }

        var recovered = 0
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let old = try decoder.decode(PromptLists.self, from: Data(contentsOf: file))
            try store.updatePersisting { metadata in
                var ids = Set(metadata.savedPrompts.map(\.id))
                for var prompt in old.prompts where ids.insert(prompt.id).inserted {
                    if prompt.schedule != nil {
                        prompt.isEnabled = false
                    }
                    metadata.savedPrompts.append(prompt)
                    recovered += 1
                }
            }
        } catch CocoaError.fileReadNoSuchFile where FileManager.default.fileExists(atPath: file.path) == false {
            // No prior installation.
        } catch {
            throw SessionServiceError("Restoring prompts from " + file.path + ": " + error.localizedDescription)
        }
        defaults.set(true, forKey: promptBackfillKey)
        return recovered
    }

    private static let promptBackfillKey = "agentidePromptsBackfilled"
}

// MARK: - PromptLists

private struct PromptLists: Decodable {
    // MARK: Lifecycle

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompts = try (container.decodeIfPresent([SavedPrompt].self, forKey: .savedPrompts) ?? [])
            + (container.decodeIfPresent([SavedPrompt].self, forKey: .scheduledPrompts) ?? [])
    }

    // MARK: Internal

    let prompts: [SavedPrompt]

    // MARK: Private

    private enum CodingKeys: CodingKey {
        case savedPrompts
        case scheduledPrompts
    }
}
