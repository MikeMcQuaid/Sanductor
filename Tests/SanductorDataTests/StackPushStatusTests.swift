import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct StackPushStatusTests {
    @Test
    func `merging a lower layer does not make published patches need another push`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let repo = world.repository.path
        func git(_ arguments: String...) async throws {
            try await TestSupport.runGit(arguments, in: repo)
        }
        try await git("remote", "add", "origin", repo)
        try await git("checkout", "-b", "lower")
        try "lower".write(toFile: repo + "/lower", atomically: true, encoding: .utf8)
        try await git("add", "lower")
        try await git("commit", "-m", "Lower")
        try await git("update-ref", "refs/remotes/origin/lower", "lower")
        try await git("branch", "--set-upstream-to=origin/lower", "lower")
        try await git("checkout", "-b", "upper")
        try "upper".write(toFile: repo + "/upper", atomically: true, encoding: .utf8)
        try await git("add", "upper")
        try await git("commit", "-m", "Upper")
        try await git("update-ref", "refs/remotes/origin/upper", "upper")
        try await git("branch", "--set-upstream-to=origin/upper", "upper")
        try await git("checkout", "main")
        try await git("merge", "--squash", "lower")
        try await git("commit", "-m", "Merged lower layer")
        try await git("update-ref", "refs/remotes/origin/main", "main")
        try await git("update-ref", "-d", "refs/remotes/origin/lower")
        try await git("branch", "restacked", "upper")
        try await git("rebase", "--onto", "main", "lower", "restacked")
        try await git("update-ref", "refs/remotes/origin/upper", "restacked")
        func needsPush(_ branch: String) async throws -> Bool {
            try await git("checkout", branch)
            let items = await world.service.overview().groups.flatMap(\.items)
            let item = try #require(items.first { $0.worktree.branch == branch })
            return item.needsPush(hasPullRequest: false, lastPush: nil)
        }
        #expect(try await needsPush("lower") == false)
        #expect(try await needsPush("upper") == false)
        try "changed".write(toFile: repo + "/upper", atomically: true, encoding: .utf8)
        try await git("commit", "-am", "New upper work")
        #expect(try await needsPush("upper"))
    }
}
