import SanductorData
import SanductorDomain
import SwiftUI
import TerminalUI

/// A picker's GitHub search, only for a list the picker limit may
/// have cut short: a shorter one already holds every open one.
extension AgentSessionForm {
    func lookUp<Item>(
        _ listed: [Item],
        search: @escaping @MainActor (Repository, String) async -> [Item],
    ) -> (@MainActor (String) async -> [Item])? {
        guard let repository, listed.count >= GitHubClient.pickerLimit else {
            return nil
        }

        return { await search(repository, $0) }
    }
}

// MARK: - AgentSessionForm.SourcePicker

/// The pick for a GitHub source, split from the form's file for
/// length: open issues or pull requests, several at once where the
/// form allows it, or one security advisory.
extension AgentSessionForm {
    struct SourcePicker: View {
        // MARK: Internal

        let source: PromptSource
        let repository: Repository?
        let picksSeveral: Bool
        @Binding var issueNumbers: Set<Int>
        @Binding var pullRequestNumbers: Set<Int>
        @Binding var ghsaID: String?

        let issues: [IssueSummary]
        let pullRequests: [PullRequestSummary]
        let advisories: [SecurityAdvisorySummary]
        let isLoadingSources: Bool
        let isLoadingAdvisories: Bool
        let reloadAdvisories: @MainActor () async -> Void
        /// GitHub's search past each list, nil once the list holds
        /// every open one.
        let searchIssues: (@MainActor (String) async -> [IssueSummary])?
        let searchPullRequests: (@MainActor (String) async -> [PullRequestSummary])?

        var body: some View {
            if repository == nil {
                Text("Pick a repository first.").interfaceFont(.callout).foregroundStyle(.secondary)
            } else if source == .issue {
                ReferencedItemPicker(
                    "Issue",
                    selection: $issueNumbers,
                    allowsSeveral: picksSeveral,
                    items: issues,
                    placeholder: "Choose an open issue",
                    searchPrompt: "Find an issue by number or title",
                    loadingTitle: "Listing open issues…",
                    emptyTitle: "No open issues",
                    isLoading: isLoadingSources,
                    lookUp: searchIssues,
                )
                // What a lookup found belongs to one repository.
                .id(repository?.id ?? "")
                .hoverHelp(
                    picksSeveral
                        ? "The repository's open issues; the pick becomes the prompt, each checked one its own session"
                        : "The repository's open issues; the pick becomes the prompt",
                )
            } else if source == .advisory {
                ReferencedItemPicker(
                    "Security advisory",
                    selection: advisoryPick,
                    allowsSeveral: false,
                    items: advisories,
                    placeholder: "Choose an advisory in triage or draft",
                    searchPrompt: "Find an advisory by GHSA id or title",
                    loadingTitle: "Listing advisories in triage or draft…",
                    emptyTitle: "No advisories in triage or draft",
                    isLoading: isLoadingAdvisories,
                )
                .hoverHelp(
                    "The repository's security advisories still in triage or draft; the pick becomes the prompt,"
                        + " and the agent is told to keep its commits and pull request quiet about it",
                )
                .task(id: repository?.id ?? "") { await reloadAdvisories() }
            } else {
                ReferencedItemPicker(
                    "Pull request",
                    selection: $pullRequestNumbers,
                    allowsSeveral: picksSeveral,
                    items: pullRequests,
                    placeholder: "Choose an open pull request",
                    searchPrompt: "Find a pull request by number or title",
                    loadingTitle: "Listing open pull requests…",
                    emptyTitle: "No open pull requests",
                    isLoading: isLoadingSources,
                    lookUp: searchPullRequests,
                )
                .id(repository?.id ?? "")
                .hoverHelp(
                    picksSeveral
                        ? "The repository's open pull requests; each checked one gets its own worktree and session"
                        : "The repository's open pull requests; its branch is checked out to work on directly",
                )
            }
        }

        // MARK: Private

        /// The advisory picker's one pick, as the picker's set.
        private var advisoryPick: Binding<Set<String>> {
            Binding(
                get: { Set([ghsaID].compactMap(\.self)) },
                set: { ghsaID = $0.first },
            )
        }
    }
}
