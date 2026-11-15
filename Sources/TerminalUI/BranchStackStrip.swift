import SanductorData
import SanductorDomain
import SwiftUI

/// The stack a worktree's branch belongs to, bottom first, with the
/// checked-out one emphasised: `main ← fix_the_lexer ← use_the_lexer`.
/// One component, shown by the review and pull request surfaces
/// alike, and shown by neither when the branch stands on its own.
public struct BranchStackStrip: View {
    // MARK: Lifecycle

    /// Creates the strip. `onSelect` retargets the surrounding pane
    /// to a branch; it never checks anything out, which is a
    /// deliberate act of its own.
    @preconcurrency
    public init(
        stack: BranchStack,
        selected: String,
        worktree: Worktree,
        service: SessionService,
        onSelect: @escaping @MainActor (String) -> Void,
    ) {
        self.stack = stack
        self.selected = selected
        self.worktree = worktree
        self.service = service
        self.onSelect = onSelect
    }

    // MARK: Public

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                if let base = stack.base {
                    Text(base)
                        .foregroundStyle(.secondary)
                        .contextMenu { branchActions(base) }
                    arrow
                }
                ForEach(Array(stack.branches.enumerated()), id: \.element) { index, branch in
                    Button(branch) { onSelect(branch) }
                        .buttonStyle(.plain)
                        .contextMenu { branchActions(branch) }
                        .fontWeight(branch == selected ? .semibold : .regular)
                        .foregroundStyle(branch == stack.checkedOut ? Color.primary : .secondary)
                        .hoverHelp(help(for: branch))
                    if index < stack.branches.count - 1 {
                        arrow
                    }
                }
            }
            .interfaceFont(.caption)
            .padding(.horizontal, Self.spacing)
            .padding(.vertical, Self.verticalPadding)
        }
        .disabled(isSwitching)
        .task(id: [worktree.path, stack.checkedOut, stack.base ?? "", String(cacheGeneration)] + stack.branches) {
            availableBranches = await Set(service.availableBranches(worktree: worktree))
            await withTaskGroup(of: (String, String?).self) { tasks in
                for branch in stack.branches {
                    tasks.addTask {
                        let summaries = try? await service.pullRequestReads.listing(
                            repositoryPath: worktree.repositoryPath, scope: .branch(branch),
                        )
                        return (branch, summaries?.first { $0.state == "OPEN" }?.url)
                    }
                }
                for await (branch, url) in tasks where Task.isCancelled == false {
                    pullRequestURLs[branch] = url
                }
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let verticalPadding: CGFloat = 3

    @State private var pullRequestURLs: [String: String] = [:]
    @State private var availableBranches: Set<String> = []
    @State private var isSwitching = false
    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var cacheGeneration = 0

    private let stack: BranchStack
    private let selected: String
    private let worktree: Worktree
    private let service: SessionService

    private let onSelect: @MainActor (String) -> Void

    private var arrow: some View {
        Text(verbatim: "←")
            .foregroundStyle(.tertiary)
            .interfaceFont(.caption)
    }

    @ViewBuilder
    private func branchActions(_ branch: String) -> some View {
        CopyBranchNameButton(branch)
        if let url = pullRequestURLs[branch] {
            CopyPullRequestURLButton(url)
        }
        if worktree.allowsSwitch(to: branch, defaultBranch: stack.base) {
            BusyButton("Switch to branch", busy: "Switching…", disabled: availableBranches.contains(branch) == false) {
                isSwitching = true
                defer { isSwitching = false }
                do {
                    try await service.switchBranch(branch, worktree: worktree)
                    StackSelection.remember(branch, for: worktree.path)
                    availableBranches = await Set(service.availableBranches(worktree: worktree))
                } catch {
                    ErrorLog.shared.report(error.localizedDescription)
                }
            }
        }
    }

    private func help(for branch: String) -> String {
        if branch == stack.checkedOut {
            "The branch this worktree holds; its diff is the one you can change"
        } else {
            "Show this branch's own changes; checking it out is a separate step"
        }
    }
}
