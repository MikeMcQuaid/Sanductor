import SanductorData
import SanductorDomain
import SwiftUI
import TerminalUI

// MARK: - LaunchDraft

/// What a launch was asked to do, as its form would show it again.
struct LaunchDraft: Equatable {
    let text: String
    let source: AgentSessionForm.PromptSource
    let agent: AgentKind
    let options: AgentLaunchOptions
    var number: Int?
    var ghsaID: String?
    var base: String?
}

// MARK: - LaunchRetry

/// A draft on its way to a form: a failed launch's back to the one
/// that started it, the new session form or a worktree's own at
/// `worktreePath`, or a pull request list's to the new session form.
/// The repository matters too: a new session form still showing
/// another repository takes the draft only once it has switched,
/// since switching resets the picks.
struct LaunchRetry: Equatable {
    let repositoryPath: String
    let worktreePath: String?
    let draft: LaunchDraft
}

// MARK: - LaunchFailure

/// A launch that failed, kept on the row it was for so the error
/// stays beside that work rather than taking over whatever the
/// window shows by the time it fails.
public struct LaunchFailure: Equatable, Sendable {
    // MARK: Public

    public let message: String

    // MARK: Internal

    /// What Edit and retry puts back in the form.
    let draft: LaunchDraft
}

// MARK: - LaunchFailureView

/// A failed launch in its row's pane: what went wrong, then the ways
/// to run it again, as it was or from the form with what was typed,
/// or away from it.
public struct LaunchFailureView: View {
    // MARK: Lifecycle

    /// Creates the block; `retryIsPrimary` is false where the pane
    /// already has a primary action, such as a worktree's own form.
    public init(worktree: Worktree, failure: LaunchFailure, model: DashboardModel, retryIsPrimary: Bool) {
        self.worktree = worktree
        self.failure = failure
        self.model = model
        self.retryIsPrimary = retryIsPrimary
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Label("The agent did not start", systemImage: "exclamationmark.triangle.fill")
                .interfaceFont(.headline)
            Text(failure.message)
                .interfaceFont(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            HStack {
                Spacer()
                if worktree.isPlaceholder {
                    Button("Dismiss") { model.dismissLaunchFailure(for: worktree) }
                        .buttonStyle(.glass)
                        .hoverHelp("Remove this row; nothing was created")
                }
                editAndRetryButton.buttonStyle(.glass)
                if retryIsPrimary {
                    retryButton.buttonStyle(.glassProminent)
                } else {
                    retryButton.buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private let worktree: Worktree
    private let failure: LaunchFailure
    private let model: DashboardModel
    private let retryIsPrimary: Bool

    private var retryButton: some View {
        Button("Retry") {
            Task {
                await model.relaunch(for: worktree)
            }
        }
        .disabled(model.canRelaunch(worktree) == false)
        .hoverHelp("Start this launch again exactly as it was asked for")
    }

    private var editAndRetryButton: some View {
        Button("Edit and retry") { model.retryLaunch(for: worktree) }
            .hoverHelp(
                worktree.isPlaceholder
                    ? "Open the new session form as this launch was started: what was typed, its source and base branch"
                    : "Put what was typed and its source back in the form below",
            )
    }
}

// MARK: - DashboardModel

public extension DashboardModel {
    /// The failure to show on a row; a session running there since
    /// has settled it.
    func launchFailure(for item: WorktreeItem) -> LaunchFailure? {
        if item.session == nil {
            launchFailures[item.worktree.path]
        } else {
            nil
        }
    }

    /// Drops a failure, and with it a placeholder's row, which hands
    /// a selection it held to its repository's checkout.
    func dismissLaunchFailure(for worktree: Worktree) {
        launchFailures[worktree.path] = nil
        guard worktree.isPlaceholder else {
            return
        }

        if selection?.worktree.path == worktree.path {
            selectMainCheckout(of: repository(of: worktree))
        }
        forgetPlaceholder(worktree)
    }

    /// Hands a failed launch's draft back to the form that started
    /// it: a placeholder gives way to the new session form on its
    /// repository and base, and a worktree's own form is already on
    /// screen.
    func retryLaunch(for worktree: Worktree) {
        guard let failure = launchFailures[worktree.path] else {
            return
        }

        let owner = repository(of: worktree)
        dismissLaunchFailure(for: worktree)
        launchRetry = LaunchRetry(
            repositoryPath: worktree.repositoryPath,
            worktreePath: worktree.isPlaceholder ? nil : worktree.path,
            draft: failure.draft,
        )
        if worktree.isPlaceholder {
            openNewSession(for: owner, base: failure.draft.base)
        }
    }

    /// Whether a failed launch can start again now: a pull request
    /// allows one launch at a time, so its draft waits on its row
    /// while another runs.
    func canRelaunch(_ worktree: Worktree) -> Bool {
        guard let draft = launchFailures[worktree.path]?.draft, let owner = repository(of: worktree) else {
            return false
        }
        guard draft.source == .pullRequest, let number = draft.number else {
            return true
        }

        return isLaunching(pullRequest: number, in: owner) == false
    }

    /// Starts a failed launch again exactly as it was asked for: a
    /// placeholder gives way to a fresh row, and a worktree keeps its
    /// own. Only a selected row takes the screen, so a retry from
    /// another row's context menu moves nothing.
    func relaunch(for worktree: Worktree) async {
        guard canRelaunch(worktree),
              let draft = launchFailures[worktree.path]?.draft,
              let owner = repository(of: worktree)
        else {
            return
        }

        let reveals = selection?.worktree.path == worktree.path
        if worktree.isPlaceholder {
            dismissLaunchFailure(for: worktree)
            await createSession(from: draft, in: owner, reveals: reveals)
        } else {
            await launchAgent(from: draft, in: worktree, repository: owner, reveals: reveals)
        }
    }

    /// The log a row's launch narrates into, or the shared one that
    /// resumes use.
    func launchProgress(for item: WorktreeItem) -> LaunchProgress {
        launchProgresses[item.worktree.path] ?? launchProgress
    }

    private func repository(of worktree: Worktree) -> Repository? {
        groups.group(holding: worktree)?.repository
    }

    private func createSession(from draft: LaunchDraft, in repository: Repository, reveals: Bool) async {
        switch draft.source {
        case .prompt:
            await createSession(
                repository: repository,
                prompt: draft.text,
                agent: draft.agent,
                options: draft.options,
                baseBranch: draft.base,
                reveals: reveals,
            )

        case .issue:
            guard let number = draft.number else {
                return
            }

            await createSession(
                fromIssue: number,
                repository: repository,
                context: draft.text,
                agent: draft.agent,
                options: draft.options,
                baseBranch: draft.base,
                reveals: reveals,
            )

        case .pullRequest:
            await createSession(fromPullRequestIn: draft, repository: repository, reveals: reveals)

        case .advisory:
            guard let ghsaID = draft.ghsaID else {
                return
            }

            await createSession(
                fromAdvisory: ghsaID,
                repository: repository,
                context: draft.text,
                agent: draft.agent,
                options: draft.options,
                baseBranch: draft.base,
                reveals: reveals,
            )
        }
    }

    private func launchAgent(
        from draft: LaunchDraft, in worktree: Worktree, repository: Repository, reveals: Bool,
    ) async {
        switch draft.source {
        case .prompt:
            await launchAgent(
                in: worktree, prompt: draft.text, agent: draft.agent, options: draft.options, reveals: reveals,
            )

        case .issue:
            guard let number = draft.number else {
                return
            }

            await launchAgent(
                fromIssue: number,
                in: worktree,
                context: draft.text,
                agent: draft.agent,
                options: draft.options,
                reveals: reveals,
            )

        case .pullRequest:
            await createSession(fromPullRequestIn: draft, repository: repository, reveals: reveals)

        case .advisory:
            guard let ghsaID = draft.ghsaID else {
                return
            }

            await launchAgent(
                fromAdvisory: ghsaID,
                in: worktree,
                context: draft.text,
                agent: draft.agent,
                options: draft.options,
                reveals: reveals,
            )
        }
    }

    /// A pull request's launch always makes its own worktree, whichever
    /// form asked for it.
    private func createSession(
        fromPullRequestIn draft: LaunchDraft, repository: Repository, reveals: Bool,
    ) async {
        guard let number = draft.number else {
            return
        }

        await createSession(
            fromPullRequest: number,
            repository: repository,
            context: draft.text,
            agent: draft.agent,
            options: draft.options,
            reveals: reveals,
        )
    }
}
