@testable import DashboardFeature
import Foundation
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `phone PR projection updates from the authenticated host cache without fetching`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.model.groups[0].items[0] = fixture.model.groups[0].items[0].with(session: AgentSession(
            name: "session", agent: .codexCLI, status: .running, paneID: "pane",
        ))
        let summary = PullRequestSummary(
            number: 42,
            title: "Private title",
            url: "https://github.com/owner/repo/pull/42",
            headBranch: "main",
            mergeable: "CONFLICTING",
            reviewDecision: "CHANGES_REQUESTED",
            checks: "FAILURE",
            body: "Private body",
        )
        fixture.model.pullRequests.rememberBranchSummary(
            summary, repositoryPath: fixture.repository.path, branch: "main",
        )
        fixture.model.cacheSidebar(fixture.model.groups)
        let file = URL(filePath: fixture.root + "/shared/sanductor/sidebar-sanductor-dev.json")
        let data = try Data(contentsOf: file)
        let sidebar = try JSONDecoder().decode([SidebarRepository].self, from: data)
        #expect(sidebar.first?.entries.first?.pullRequest == SidebarPullRequest(summary))
        #expect(String(data: data, encoding: .utf8)?.contains("Private") == false)
        #expect(sidebar.first?.entries.first?.pullRequest?.details != nil)
        #expect(sidebar.first?.entries.first?.status == .ciFailing)

        fixture.model.pullRequests.rememberBranchSummary(nil, repositoryPath: fixture.repository.path, branch: "main")
        fixture.model.cacheSidebar(fixture.model.groups)
        #expect(try JSONDecoder()
            .decode([SidebarRepository].self, from: Data(contentsOf: file))
            .first?
            .entries
            .first?
            .pullRequest == nil)
    }

    @Test
    func `phone sidebar publishes public owners and ordered worktrees only when changed`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let original = try #require(fixture.model.groups.first?.items.first).with(session: AgentSession(
            name: "session", agent: nil, status: .running, paneID: "pane",
        ))
        let host = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: fixture.repository.path,
                branch: "Private directory",
                path: "/private/directory",
                isHostDirectory: true,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        let groups = [
            RepositoryGroup(
                repository: Repository(name: "repo", path: fixture.repository.path, fullName: "Homebrew/remote-name"),
                items: [original, host],
                defaultBranch: "main",
            ),
        ]
        fixture.model.groups = groups
        fixture.model.cacheSidebar(groups)
        let file = fixture.root + "/shared/sanductor/sidebar-sanductor-dev.json"
        #expect(try JSONDecoder().decode([SidebarRepository].self, from: Data(contentsOf: URL(filePath: file))) == [
            SidebarRepository(
                name: "repo",
                owner: "Homebrew",
                worktrees: [fixture.repository.path],
                entries: [
                    SidebarEntry(
                        target: SidebarTarget(original.worktree), status: .defaultBranch, activity: nil, block: nil,
                    ),
                ],
                fullName: "Homebrew/remote-name",
                defaultBranch: "main",
            ),
        ])
        #expect(FileManager.default.fileExists(
            atPath: fixture.root + "/shared/sanductor/sidebar-sanductor.json",
        ) == false)

        let timestamp = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file)
        fixture.model.cacheSidebar(groups)
        #expect(try FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date == timestamp)

        fixture.model.cacheSidebar([])
        #expect(try JSONDecoder().decode([SidebarRepository].self, from: Data(contentsOf: URL(filePath: file))).isEmpty)
    }

    @Test(arguments: [SessionStatus.running, .finished])
    func `phone snapshot removes worktree details when its live pane closes`(status: SessionStatus) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let original = try #require(fixture.model.groups.first?.items.first)
        fixture.model.groups[0].items[0] = original.with(session: AgentSession(
            name: "session", agent: .codexCLI, status: status, paneID: "pane",
        ))
        fixture.model.cacheSidebar(fixture.model.groups)
        #expect(fixture.model.publishedSidebar.first?.entries.count == 1)
        #expect(fixture.model.publishedSidebar.first?.worktrees == [original.worktree.path])

        fixture.model.groups[0].items = [original]
        fixture.model.cacheSidebar(fixture.model.groups)
        let file = URL(filePath: fixture.root + "/shared/sanductor/sidebar-sanductor-dev.json")
        let stopped = try JSONDecoder().decode([SidebarRepository].self, from: Data(contentsOf: file))
        #expect(stopped.first?.entries.isEmpty == true)
        #expect(stopped.first?.worktrees.isEmpty == true)
        #expect(stopped.first?.name == fixture.repository.name)
        #expect(fixture.model.store.load().cachedSidebar.first?.worktrees.count == 1)
    }
}
