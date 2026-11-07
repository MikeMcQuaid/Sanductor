@testable import DashboardFeature
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension SessionNavigationTests {
    @Test
    func `a late launch failure restores its row without moving the selection`() async throws {
        let runner = FailingIssueRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let main = fixture.model.groups[0].items[0]
        let created = WorktreeItem(
            worktree: Worktree(
                repositoryName: fixture.repository.name,
                repositoryPath: fixture.repository.path,
                branch: "another_launch",
                path: fixture.repository.path + "/another_launch",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        var pending: WorktreeItem?
        await runner.beforeFailing {
            pending = fixture.model.selection
            fixture.model.groups = DashboardModel.retainingLostRows(
                of: fixture.model.groups,
                in: [RepositoryGroup(repository: fixture.repository, items: [main, created])],
            )
            fixture.model.select(created)
        }

        await fixture.model.createSession(
            fromIssue: 12, repository: fixture.repository, context: "Fix it", agent: .claudeCode,
        )

        let placeholder = try #require(pending)
        #expect(fixture.model.worktreePaths.contains(placeholder.worktree.path))
        #expect(fixture.model.launchFailure(for: placeholder) != nil)
        #expect(fixture.model.selection?.id == created.id)
        #expect(fixture.model.deletingPaths.contains(placeholder.worktree.path) == false)
        #expect(fixture.model.launchProgresses.isEmpty)
    }

    @Test(arguments: [true, false])
    func `retrying a failed placeholder starts the same work on a fresh row`(isSelected: Bool) async throws {
        let runner = FailingIssueRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let main = fixture.model.groups[0].items[0]
        await fixture.model.createSession(
            fromIssue: 12,
            repository: fixture.repository,
            context: "Fix it",
            agent: .codexCLI,
            options: AgentLaunchOptions(model: "test-model", effort: "low"),
            baseBranch: "part_one",
        )
        let failed = try #require(fixture.model.selection)
        let draft = try #require(fixture.model.launchFailure(for: failed)?.draft)
        if isSelected == false {
            fixture.model.select(main)
            fixture.model.showsNewSession = true
        }

        await fixture.model.relaunch(for: failed.worktree)

        #expect(await runner.issueReads == 2)
        #expect(fixture.model.launchFailures.count == 1)
        #expect(fixture.model.launchFailures.values.first?.draft == draft)
        #expect(fixture.model.launchFailures[failed.worktree.path] == nil)
        #expect(fixture.model.worktreePaths.contains(failed.worktree.path) == false)
        #expect((fixture.model.selection?.isPlaceholder ?? false) == isSelected)
        #expect(fixture.model.showsNewSession == (isSelected == false))
    }

    @Test
    func `retrying an adopted worktree finds the group that lists it`() async {
        let runner = FailingIssueRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let adopted = Worktree(
            repositoryName: fixture.repository.name,
            repositoryPath: fixture.repository.path + "/.base",
            branch: "adopted",
            path: fixture.repository.path + "/adopted",
        )
        fixture.model.groups[0].items.append(
            WorktreeItem(worktree: adopted, session: nil, isDirty: false, aheadOfUpstream: nil),
        )
        await fixture.model.launchAgent(fromIssue: 12, in: adopted, context: "Fix it", agent: .codexCLI)

        await fixture.model.relaunch(for: adopted)

        #expect(await runner.issueReads == 2)
    }

    @Test
    func `a pull request launching elsewhere keeps a failed retry's row and draft`() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let placeholder = Worktree(
            repositoryName: fixture.repository.name,
            repositoryPath: fixture.repository.path,
            branch: "pr-7",
            path: fixture.repository.path + DashboardModel.placeholderMarker + "pr-7-failed",
        )
        fixture.model.groups[0].items.append(
            WorktreeItem(worktree: placeholder, session: nil, isDirty: false, aheadOfUpstream: nil),
        )
        let draft = LaunchDraft(text: "", source: .pullRequest, agent: .claudeCode, options: .init(), number: 7)
        fixture.model.launchFailures[placeholder.path] = LaunchFailure(message: "fetch failed", draft: draft)
        let running = fixture.repository.path + DashboardModel.placeholderMarker + "pr-7-running"
        #expect(fixture.model.canRelaunch(placeholder))
        fixture.model.launchProgresses[running] = LaunchProgress()

        await fixture.model.relaunch(for: placeholder)

        #expect(fixture.model.canRelaunch(placeholder) == false)
        #expect(fixture.model.launchFailures[placeholder.path]?.draft == draft)
        #expect(fixture.model.worktreePaths.contains(placeholder.path))
    }

    @Test(arguments: [
        (selected: false, reveals: true, opens: true),
        (selected: false, reveals: false, opens: false),
        (selected: true, reveals: false, opens: true),
    ])
    func `a finished launch takes an empty selection only when it reveals`(
        selected: Bool, reveals: Bool, opens: Bool,
    ) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let row = try #require(fixture.model.groups[0].items.first)
        fixture.model.selection = selected ? row : nil

        #expect(fixture.model.opensPane(ofRowAt: row.worktree.path, reveals: reveals) == opens)
    }

    @Test(arguments: [true, false])
    func `retrying a failed worktree launch keeps its row`(isSelected: Bool) async {
        let runner = FailingIssueRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let main = fixture.model.groups[0].items[0]
        let worktree = main.worktree
        fixture.model.discoveredModels[.codexCLI] = ["test-model"]
        await fixture.model.launchAgent(
            fromIssue: 12,
            in: worktree,
            context: "Fix it",
            agent: .codexCLI,
            options: AgentLaunchOptions(model: "test-model", effort: "low"),
        )
        let draft = fixture.model.launchFailures[worktree.path]?.draft
        fixture.model.selection = isSelected ? main : nil
        fixture.model.showsNewSession = true

        await fixture.model.relaunch(for: worktree)

        #expect(await runner.issueReads == 2)
        #expect(draft != nil)
        #expect(fixture.model.launchFailures[worktree.path]?.draft == draft)
        #expect(fixture.model.launchProgresses.isEmpty)
        #expect(fixture.model.showsNewSession == (isSelected == false))
    }
}

// MARK: - FailingIssueRunner

private actor FailingIssueRunner: ProcessRunner {
    // MARK: Internal

    private(set) var issueReads = 0

    func beforeFailing(_ action: @escaping @MainActor @Sendable () -> Void) {
        beforeFailure = action
    }

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) async -> ProcessResult {
        if arguments.contains("issue"), arguments.contains("view") {
            issueReads += 1
            await beforeFailure?()
            beforeFailure = nil
            return ProcessResult(status: 1, standardOutput: "", standardError: "Issue unavailable")
        }
        return ProcessResult(status: 0, standardOutput: "[]", standardError: "")
    }

    // MARK: Private

    private var beforeFailure: (@MainActor @Sendable () -> Void)?
}
