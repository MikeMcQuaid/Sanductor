import Foundation
import SanductorData
import SanductorDomain

extension PullRequestsModel {
    // MARK: Internal

    /// Writes the disclosure only into the template's own AI section.
    func discloseInTemplate() {
        guard let disclosure, let ticked = Self.disclosing(in: prTemplate, sentence: disclosure) else {
            return
        }

        prTemplate = ticked
    }

    /// The last recorded agent in this worktree, falling back to its own session history.
    var disclosure: String? {
        guard let worktree = listedWorktree else {
            return nil
        }

        let metadata = store.load()
        let holder = items.first { item in
            item.worktree.repositoryPath == worktree.repositoryPath && item.worktree.branch == worktree.branch
        } ?? branchItem
        let session = holder?.session?.name ?? holder.flatMap { metadata.sessionsByWorktree[$0.worktree.path] }
        let recorded = WorktreeAgent(at: holder?.worktree.path ?? worktree.path)
        guard let agent = recorded?.agent ?? holder?.session?.agent ?? session.flatMap({ name in
            AgentKind.allCases.first { name.hasSuffix("--" + $0.rawValue) }
        }) ?? holder?.pastSessions.first?.agent else {
            return nil
        }

        let arguments = recorded?.arguments ?? session.flatMap { metadata.arguments[$0] } ?? ""
        let choices = launchChoices(agent)
        let model = Self.model(inArguments: arguments) ?? (recorded == nil ? choices.models.first : nil)
        let effort = Self.effort(inArguments: arguments) ?? (recorded == nil ? choices.defaultEffort : nil)
        let named = model.map { " with " + AgentOptionName.display($0, named: choices.names) } ?? ""
        let level = effort.map { " at " + AgentOptionName.display($0) + " effort" } ?? ""
        return agent.displayName + named + level + ", with local review and testing."
    }

    /// The model out of the arguments a session was started with;
    /// both agents name it the same way.
    static func model(inArguments arguments: String) -> String? {
        let tokens = arguments.split(separator: " ").map(String.init)
        guard let flag = tokens.firstIndex(of: "--model"), tokens.count > flag + 1 else {
            return nil
        }

        return tokens[flag + 1]
    }

    /// The effort, which Claude Code takes as a flag and Codex as a
    /// configuration override.
    static func effort(inArguments arguments: String) -> String? {
        let tokens = arguments.split(separator: " ").map(String.init)
        if let flag = tokens.firstIndex(of: "--effort"), tokens.count > flag + 1 {
            return tokens[flag + 1]
        }

        return tokens
            .first { $0.hasPrefix(Self.codexEffort) }
            .map { String($0.dropFirst(Self.codexEffort.count)) }
    }

    /// How Codex spells its effort in a session's arguments.
    private static let codexEffort = "model_reasoning_effort="

    /// The template with its AI checkbox ticked and the sentence
    /// under it, or nil when the template asks for no disclosure.
    /// The sentence goes after the guidance comment, where the
    /// template says to put it, and replaces one written before so
    /// pressing twice says it once.
    static func disclosing(in template: String, sentence: String) -> String? {
        var lines = template.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let box = lines.firstIndex(where: { $0.contains("AI/LLM") }) else {
            return nil
        }

        lines[box] = lines[box].replacing("- [ ]", with: "- [x]").replacing("* [ ]", with: "* [x]")
        let comment = lines[box...].firstIndex { $0.contains("-->") } ?? box
        let after = lines.index(after: comment)
        if let existing = lines[after...].firstIndex(where: { $0.hasSuffix("with local review and testing.") }) {
            lines[existing] = sentence
            return lines.joined(separator: "\n")
        }

        lines.insert(contentsOf: ["", sentence], at: after)
        return lines.joined(separator: "\n")
    }
}

// MARK: - LaunchChoices

/// What a session would have been started with, for reading back what
/// one was: the models an agent offers, the effort it defaults to and
/// the fuller names it reports for either.
struct LaunchChoices {
    var models: [String] = []
    var defaultEffort: String?
    var names: [String: String] = [:]
}
