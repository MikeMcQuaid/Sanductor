import Foundation
import SanductorDomain

public extension PortableSettings {
    /// Merge the old library once. Thereafter the file owns definitions and the Mac owns launch history.
    func restorePrompts(in store: MetadataStore) throws {
        try backup.update { values in
            var file = values ?? [:]
            let legacy = file["promptSharingVersion"] as? Int != Self.libraryVersion
            var templates = try Self.promptLibrary(in: file)
            let existing = try store.loadChecked().savedPrompts
            guard Set(existing.map(\.id)).count == existing.count else {
                throw SessionServiceError("Duplicate saved prompt ID in " + store.file)
            }

            let backfill = legacy || importedBackupPath != backup.destination.path
            var restored = [SavedPrompt]()
            for local in existing {
                if let saved = templates.removeValue(forKey: local.id.uuidString) {
                    restored.append(legacy || Template(local) == saved ? local : saved.applying(to: local))
                } else if backfill {
                    restored.append(local)
                }
            }
            restored += try templates.sorted { $0.key < $1.key }.map { key, template in
                var prompt = SavedPrompt()
                prompt.id = try Self.promptID(key)
                return template.applying(to: prompt)
            }
            file["savedPrompts"] = try Self.plist(Dictionary(
                uniqueKeysWithValues: restored.map { ($0.id.uuidString, Template($0)) },
            ))
            file["promptSharingVersion"] = Self.libraryVersion as NSObject
            if restored != existing {
                try store.updatePersisting { $0.savedPrompts = restored }
            }
            return file
        }
        importedBackupPath = backup.destination.path
    }

    /// Write one definition so a concurrent editor's other prompts survive.
    func savePrompt(_ prompt: SavedPrompt) throws {
        try changePrompt(id: prompt.id, to: Template(prompt))
    }

    /// Remove the deleted definition from the private backup.
    func deletePrompt(id: UUID) throws {
        try changePrompt(id: id, to: nil)
    }

    internal static func mergedPrompts(legacy: [String: NSObject], backup: [String: NSObject]) throws -> NSObject {
        try plist(promptLibrary(in: legacy).merging(promptLibrary(in: backup)) { _, saved in saved })
    }

    private struct Template: Codable, Equatable {
        // MARK: Lifecycle

        init(_ saved: SavedPrompt) {
            name = saved.name
            prompt = saved.prompt
            schedule = saved.schedule
            if saved.schedule != nil {
                repositoryPath = saved.repositoryPath
                agent = saved.agent
                model = saved.model
                effort = saved.effort
            }
        }

        // MARK: Internal

        let name: String
        let prompt: String
        let schedule: PromptSchedule?
        var repositoryPath: String?
        var agent: AgentKind?
        var model: String?
        var effort: String?

        func applying(to local: SavedPrompt) -> SavedPrompt {
            var saved = local
            saved.name = name
            saved.prompt = prompt
            saved.schedule = schedule
            saved.repositoryPath = repositoryPath ?? ""
            saved.agent = agent ?? .claudeCode
            saved.model = model ?? ""
            saved.effort = effort ?? ""
            saved.isEnabled = schedule == nil
            saved.nextRun = nil
            return saved
        }
    }

    private static let libraryVersion = 2

    private static func promptID(_ key: String) throws -> UUID {
        guard let id = UUID(uuidString: key) else {
            throw SessionServiceError("Invalid saved prompt ID in settings.plist")
        }

        return id
    }

    private func changePrompt(id: UUID, to prompt: Template?) throws {
        try backup.update { values in
            var file = values ?? [:]
            var prompts = try Self.promptLibrary(in: file)
            prompts[id.uuidString] = prompt
            file["savedPrompts"] = try Self.plist(prompts)
            file["promptSharingVersion"] = Self.libraryVersion as NSObject
            return file
        }
        privateSettingsChanged?()
    }

    private static func promptLibrary(in file: [String: NSObject]) throws -> [String: Template] {
        guard (file["promptSharingVersion"] as? Int ?? 0) <= libraryVersion else {
            throw SessionServiceError("This prompt library needs a newer Sanductor.")
        }
        guard let value = file["savedPrompts"] else {
            return [:]
        }

        let templates = try decode([String: Template].self, from: value)
        var validated = [String: Template]()
        for (key, template) in templates {
            let id = try promptID(key).uuidString
            guard validated[id] == nil, template.applying(to: SavedPrompt()).isValid,
                  template.schedule.map({ $0.nextRun(after: Date()) != nil }) ?? true
            else {
                throw SessionServiceError("Invalid saved prompt in settings.plist")
            }

            validated[id] = template
        }
        return validated
    }
}
