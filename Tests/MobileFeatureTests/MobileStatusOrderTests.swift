import Foundation
@testable import MobileFeature
import SanductorDomain
import SanductorRemote
import Testing

struct MobileStatusOrderTests {
    @Test
    func `finishing a turn after a stack merge honours the Mac's patch comparison`() throws {
        let wire = """
        {"target":{"repository":"repo","repositoryPath":"/repo","branch":"work","path":"/tree"},
         "status":"Working","activity":{"working":{}},"paneID":"pane","hasUnpushedCommits":false}
        """
        let entry = try JSONDecoder().decode(SidebarEntry.self, from: Data(wire.utf8))
        let repo = SidebarRepository(name: "repo", owner: nil, worktrees: ["/tree"], entries: [entry])
        let session = MobileSession(
            id: "pane",
            name: "repo",
            repository: "repo",
            branch: "work",
            agent: .codexCLI,
            activity: .done,
            directory: "/tree",
            gitStatus: GitWorktreeStatus(branch: "work", isDirty: false, aheadOfUpstream: 2, behindUpstream: 1),
        )
        #expect(session.sidebarEntry(in: [repo])?.status == .done)
    }

    @Test(arguments: [SidebarStatus.needsPush, .waitingForCI, .waitingForReview])
    func `status groups show the newest event across repositories first`(status: SidebarStatus) throws {
        let model = MobileModel(configuration: SSHConfiguration())
        model.allRepositories = ["first", "second"]
        model.allSessions = model.allRepositories.map { name in
            MobileSession(
                id: name,
                name: name,
                repository: name,
                branch: "work",
                agent: .codexCLI,
                activity: .done,
                directory: "/" + name,
            )
        }
        model.sidebar = try model.allRepositories.enumerated().map { offset, name in
            let wire = """
            {"target":{"repository":"\(name)","repositoryPath":"/repo","branch":"work","path":"/\(name)"},
             "status":"Done","workflowStatus":"\(status.rawValue)","activity":{"done":{}},"lastEventAt":\(offset + 1)}
            """
            let entry = try JSONDecoder().decode(SidebarEntry.self, from: Data(wire.utf8))
            return SidebarRepository(name: name, owner: nil, worktrees: ["/" + name], entries: [entry])
        }
        #expect(model.statusGroups.first?.status == status)
        #expect(model.statusGroups.first?.sessions.map(\.id) == ["second", "first"])
    }
}
