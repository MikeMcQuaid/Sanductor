import SanductorData
import SanductorDomain
import SanductorInterface
import SwiftUI

/// The pick for a GitHub source, split from the form's file for
/// length: open issues or pull requests, several at once where the
/// form allows it, or one security advisory or discussion.
extension AgentSessionForm {
    struct SourcePicker: View {
        // MARK: Internal

        let model: DashboardModel
        let source: PromptSource
        let repository: Repository?
        let picksSeveral: Bool
        @Binding var issueNumbers: Set<Int>
        @Binding var pullRequestNumbers: Set<Int>
        @Binding var ghsaID: String?
        @Binding var discussionURL: String?

        let issues: [IssueSummary]
        let pullRequests: [PullRequestSummary]
        let isLoadingSources: Bool

        var body: some View {
            picker.task(id: source) { await reload() }
        }

        // MARK: Private

        /// Advisory titles stay in memory only while this form is open.
        @State private var advisories: [SecurityAdvisorySummary] = []
        @State private var discussions: [DiscussionSummary] = []
        @State private var scope = ""
        @State private var isLoading = true

        @ViewBuilder private var picker: some View {
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
                    lookUp: lookUp(issues, search: model.searchOpenIssues(repository:query:)),
                )
                .hoverHelp(
                    picksSeveral
                        ? "The repository's open issues; the pick becomes the prompt, each checked one its own session"
                        : "The repository's open issues; the pick becomes the prompt",
                )
            } else if source == .advisory {
                ReferencedItemPicker(
                    "Security advisory",
                    selection: singleSelection($ghsaID),
                    allowsSeveral: false,
                    items: advisories,
                    placeholder: "Choose an advisory in triage or draft",
                    searchPrompt: "Find an advisory by GHSA id or title",
                    loadingTitle: "Listing advisories in triage or draft…",
                    emptyTitle: "No advisories in triage or draft",
                    isLoading: isLoading,
                )
                .hoverHelp(
                    "The repository's security advisories still in triage or draft; the pick becomes the prompt,"
                        + " and the agent is told to keep its commits and pull request quiet about it",
                )
            } else if source == .discussion {
                ReferencedItemPicker(
                    "Discussion",
                    selection: singleSelection($discussionURL),
                    allowsSeveral: false,
                    items: discussions,
                    placeholder: "Choose an open discussion",
                    searchPrompt: "Find a discussion by number or title",
                    loadingTitle: "Listing open discussions…",
                    emptyTitle: "No open discussions",
                    isLoading: isLoading,
                    lookUp: lookUp(discussions, search: searchDiscussions),
                )
                .hoverHelp("Open discussions from the repository or its organisation; the pick becomes the prompt")
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
                    lookUp: lookUp(pullRequests, search: model.searchOpenPullRequests(repository:query:)),
                )
                .hoverHelp(
                    picksSeveral
                        ? "The repository's open pull requests; each checked one gets its own worktree and session"
                        : "The repository's open pull requests; its branch is checked out to work on directly",
                )
            }
        }

        private func singleSelection(_ selection: Binding<String?>) -> Binding<Set<String>> {
            Binding(
                get: { Set([selection.wrappedValue].compactMap(\.self)) },
                set: { selection.wrappedValue = $0.first },
            )
        }

        /// A shorter list already holds every open item.
        private func lookUp<Item>(
            _ listed: [Item],
            search: @escaping @MainActor (Repository, String) async -> [Item],
        ) -> (@MainActor (String) async -> [Item])? {
            guard let repository, listed.count >= GitHubClient.pickerLimit else {
                return nil
            }

            return { await search(repository, $0) }
        }

        private func searchDiscussions(_ repository: Repository, query: String) async -> [DiscussionSummary] {
            await (try? model.github.discussions(repositoryPath: repository.path, scope: scope, query: query)) ?? []
        }

        private func reload() async {
            guard let repository else {
                return
            }

            isLoading = true
            if source == .advisory {
                let fresh = await model.securityAdvisories(repository: repository)
                guard Task.isCancelled == false else {
                    return
                }

                advisories = fresh
            } else if source == .discussion {
                let resolvedScope = await (try? model.github.discussionScope(repository: repository)) ?? ""
                guard Task.isCancelled == false else {
                    return
                }

                scope = resolvedScope
                let fresh = await searchDiscussions(repository, query: "")
                guard Task.isCancelled == false else {
                    return
                }

                discussions = fresh
            }
            isLoading = false
        }
    }
}
