@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
@testable import SanductorInterface
import Testing

extension SessionNavigationTests {
    @Test
    func `editing a dated block in another time zone preserves its deadline`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Athens"))
        let original = try Date("2026-11-20T00:00:00Z", strategy: .iso8601)
        let nextDay = try Date("2026-11-21T00:00:00Z", strategy: .iso8601)
        let localMidnight = try Date("2026-11-20T22:00:00Z", strategy: .iso8601)
        #expect(WorkBlockEditor.unblockDate(for: original, previous: original, calendar: calendar) == original)
        #expect(WorkBlockEditor.unblockDate(for: nextDay, previous: original, calendar: calendar) == localMidnight)
    }

    @Test
    func `saving a dated block keeps a stored instant after local midnight`() throws {
        let target = SidebarTarget(repository: "repo", repositoryPath: "/repo", branch: "work", path: "/work")
        let later = try Date("2099-11-20T12:00:00Z", strategy: .iso8601)
        let deadline = try #require(Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: later))
        let editor = WorkBlockEditor(
            target: target,
            block: WorkBlock(target: target, scope: .branch, dependency: .date(deadline)),
            targets: [target],
            loadSources: { _ in SidebarResponse() },
            save: { _, _ in nil },
            dismiss: { Issue.record("Reading the dependency dismissed the editor") },
        )
        #expect(editor.dependency == .date(deadline))
    }

    @Test
    func `dated blocks persist until the selected day begins`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let target = SidebarTarget(item.worktree)
        let tomorrow = try #require(Calendar.current.dateInterval(of: .day, for: .now)?.end)
        let block = WorkBlock(target: target, scope: .worktree, dependency: .date(tomorrow))
        #expect(fixture.model.editBlocks(block, targets: [target], replacing: []) == nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try Data(contentsOf: URL(filePath: fixture.root + "/state.json"))
        #expect(try decoder.decode(AppMetadata.self, from: saved).workBlocks.contains(block))
        await fixture.model.service.resolveWorkBlocks(now: tomorrow.addingTimeInterval(-1))
        fixture.model.updateWorkBlocks()
        #expect(fixture.model.block(for: item)?.dependency == .date(tomorrow))
        await fixture.model.service.resolveWorkBlocks(now: tomorrow)
        fixture.model.updateWorkBlocks()
        #expect(fixture.model.block(for: item) == nil)
    }

    @Test(arguments: ["open", "merged", "old", "removed"])
    func `worktree dependencies wait for their current work to end`(outcome: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let other = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: fixture.repository.path,
                branch: "dependency",
                path: fixture.root + "/dependency",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        fixture.model.groups = [RepositoryGroup(repository: fixture.repository, items: [item, other])]
        try FileManager.default.createDirectory(atPath: other.worktree.path, withIntermediateDirectories: true)
        let block = WorkBlock(
            target: SidebarTarget(item.worktree),
            scope: .worktree,
            dependency: .worktree(SidebarTarget(other.worktree)),
        )
        #expect(fixture.model.editBlocks(block, targets: [block.target], replacing: []) == nil)
        let createdAt = try #require(fixture.model.block(for: item)).createdAt
        let summary = PullRequestSummary(
            number: 12,
            title: "Dependency",
            url: "",
            headBranch: "dependency",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: outcome == "open" ? "OPEN" : "MERGED",
            closedAt: createdAt.addingTimeInterval(outcome == "old" ? -1 : 1),
        )
        fixture.model.pullRequests.rememberListing(
            repositoryPath: fixture.repository.path, scope: .branch("dependency"), summaries: [summary],
        )
        if outcome == "removed" {
            try FileManager.default.removeItem(atPath: other.worktree.path)
        }
        await fixture.model.refreshWorkBlocks(force: true)
        #expect((fixture.model.block(for: item) == nil) == ["merged", "removed"].contains(outcome))
    }
}
