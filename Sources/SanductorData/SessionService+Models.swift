import Foundation
import SanductorDomain

/// What models an agent offers: its own listing where it has one,
/// and nothing to ask where it has none. Split from the sources for
/// length.
public extension SessionService {
    /// Asks the agent's CLI for its current models; nil when the
    /// command fails or yields nothing. The CLI runs inside the
    /// sandbox, where sessions run it anyway; running it as the host
    /// user made macOS prompt for broad disk access.
    func discoverModels(for agent: AgentKind) async -> AgentModelCatalogue? {
        let runner = runner(for: agent)
        let argv = launcher.command(
            payload: runner.modelListingCommand.joined(separator: " "),
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "sanductor-model-listing",
        )
        let result = try? await processes.run(argv, workingDirectory: nil, environment: [:])
        guard let result, result.succeeded,
              let catalogue = runner.modelCatalogue(from: result.standardOutput), catalogue.models.isEmpty == false
        else {
            return nil
        }

        return catalogue
    }

    /// Watches agent installations and the server-managed Codex catalogue.
    func makeModelWatcher() -> WorkspaceWatcher {
        WorkspaceWatcher(
            roots: Quarantine.homebrewBinaries + [paths.sandboxHome + "/.local", paths.sandboxHome + "/.codex"],
        )
    }

    /// File identity is cheap to check even when an unrelated CLI file changes.
    func modelFilesStamp() -> String {
        let binaries = Quarantine.homebrewBinaries.flatMap { prefix in
            AgentKind.allCases.map { prefix + "/" + $0.rawValue }
        } + AgentKind.allCases.map { paths.sandboxHome + "/.local/bin/" + $0.rawValue }
        let files = binaries + [paths.sandboxHome + "/.codex/models_cache.json"]
        return files.map { path in
            let resolved = URL(filePath: path).resolvingSymlinksInPath().path
            let attributes = try? FileManager.default.attributesOfItem(atPath: resolved)
            return resolved + "#" + ((attributes?[.modificationDate] as? Date)?.description ?? "")
        }
        .joined(separator: "\n")
    }

    /// What identifies the answer a listing would give: the CLI's
    /// own version, and where the list comes from a cache the server
    /// rewrites, that file's modification time as well. Keyed on the
    /// version alone, a model added server-side stayed missing from
    /// the picker until the CLI itself was upgraded.
    func modelListingStamp(for agent: AgentKind) async -> String? {
        _ = Quarantine.clear(for: agent)
        // Invalidate catalogues from the earlier cache parser, including missing effort lists.
        let version = await probeVersion(of: agent).map { $0 + "#catalogue2" }
        guard let file = runner(for: agent).modelCacheFile else {
            return version
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: paths.sandboxHome + "/" + file)
        let modified = attributes?[.modificationDate] as? Date
        return (version ?? "") + "#" + (modified?.timeIntervalSince1970.description ?? "")
    }

    /// The fuller names an agent reports for its own models, by the
    /// name `--model` takes. Read from the file the agent keeps
    /// rather than written here, so a new version names itself the
    /// first time it is used.
    func modelNames(for agent: AgentKind) -> [String: String] {
        if let catalogue = store.load().modelCatalogues[agent.rawValue] {
            return catalogue.names
        }
        guard let file = runner(for: agent).modelNamesFile,
              let data = FileManager.default.contents(atPath: paths.sandboxHome + "/" + file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        return ClaudeModelNames.names(fromIdentifiers: Self.modelIdentifiers(inClaudeState: json))
    }

    /// Every model identifier Claude Code's state names: the options
    /// it was offered, and the usage it recorded per project.
    static func modelIdentifiers(inClaudeState json: [String: Any]) -> [String] {
        var identifiers = [String]()
        let offered = json["additionalModelOptionsCache"] as? [[String: Any]] ?? []
        identifiers += offered.compactMap { $0["value"] as? String }
        let projects = json["projects"] as? [String: Any] ?? [:]
        for project in projects.values {
            let usage = (project as? [String: Any])?["lastModelUsage"] as? [String: Any] ?? [:]
            identifiers += usage.keys
        }
        return identifiers
    }

    /// What a picker starts on for an agent: the first model it
    /// offers and the effort the CLI itself would use. A form that
    /// opens on nothing makes the first thing anyone does a choice
    /// between names they have to look up.
    func launchDefaults(for agent: AgentKind, models: [String]) -> (model: String, effort: String) {
        let model = models.first ?? ""
        let catalogue = store.load().modelCatalogues[agent.rawValue]
        let levels = catalogue?.efforts[model] ?? []
        let preferred = catalogue?.defaultEfforts[model] ?? runner(for: agent).defaultEffort ?? ""
        return (model, levels.contains(preferred) ? preferred : levels.first ?? "")
    }

    /// Rejects stale saved settings as well as combinations submitted outside the pickers.
    internal func validate(_ options: AgentLaunchOptions, for agent: AgentKind) throws {
        if options.model == nil, options.effort == nil {
            return
        }
        guard let catalogue = store.load().modelCatalogues[agent.rawValue] else {
            throw SessionServiceError("Wait for " + agent.displayName
                + " model discovery before choosing a model or effort.")
        }
        guard catalogue.supports(model: options.model, effort: options.effort) else {
            throw SessionServiceError("The selected " + agent.displayName
                + " model and effort are not supported together. Choose a current model and effort in Settings.")
        }
    }
}
