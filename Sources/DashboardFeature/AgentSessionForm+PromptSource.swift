import SanductorData
import SanductorDomain

/// Where a session's prompt comes from; split from the form's file
/// for length.
extension AgentSessionForm {
    /// What the user chose, handed to the submit action.
    struct Submission {
        let repository: Repository
        let source: PromptSource
        /// The picked issues or pull requests, one launch each.
        let numbers: [Int]
        let ghsaID: String?
        let prompt: String
        let context: String
        let agent: AgentKind
        let options: AgentLaunchOptions
        var discussionURL: String?

        func startAdvisory(model: DashboardModel, repository: Repository) async {
            guard let ghsaID else {
                return
            }

            await model.createSession(
                fromAdvisory: ghsaID,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
                baseBranch: model.newSessionBase,
            )
        }

        func startDiscussion(model: DashboardModel, repository: Repository, worktree: Worktree? = nil) async {
            guard let discussionURL else {
                return
            }

            await model.startDiscussion(
                discussionURL,
                repository: repository,
                context: context,
                agent: agent,
                options: options,
                worktree: worktree,
                baseBranch: worktree == nil ? model.newSessionBase : nil,
            )
        }
    }

    enum PromptSource: CaseIterable {
        case prompt
        case issue
        case pullRequest
        case advisory
        case discussion

        // MARK: Internal

        var title: String {
            switch self {
            case .prompt:
                "Prompt"

            case .issue:
                "Issue"

            case .pullRequest:
                "PR"

            case .discussion:
                "Discussion"

            case .advisory:
                "Advisory"
            }
        }
    }
}
