import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct ReviewCommitContextTests {
    @Test
    func `large commit selections retain every message and unpushed row in order`() async throws {
        let path = try TestSupport.temporaryDirectory("long-history")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.runGit(["init", "-q", "-b", "main"], in: path)
        let count = 4_100
        let history = (0 ... count)
            .map { index in
                "commit refs/heads/main\ncommitter Test <test@example.com> 1 +0000\n"
                    + "data <<END\nChange \(index)\nEND\n\n"
            }
            .joined()
        try history.write(toFile: path + "/history", atomically: true, encoding: .utf8)
        try await TestSupport.run(["/bin/sh", "-c", "git fast-import --quiet <history"], in: path)

        let git = GitClient(runner: FoundationProcessRunner())
        let base = "HEAD~" + String(count)
        let range = base + "..HEAD"
        let revisions = try await TestSupport.runGit(["rev-list", range], in: path)
            .standardOutput
            .split(separator: "\n")
            .map(String.init)
        #expect(revisions.count == count)
        let expected = try await git.reviewCommitContext(worktreePath: path, revisions: [range])
        #expect(try await git.reviewCommitContext(worktreePath: path, revisions: revisions) == expected)
        let rows = await git.branchCommits(worktreePath: path, baseRef: base)
        #expect(rows.count == count + 1)
        #expect(await git.unpushedCommitLines(worktreePath: path, upstreamRef: base, baseRef: nil) == rows)
    }

    @Test
    func `large committed changes include full messages and exclude later working edits`() async throws {
        let path = try TestSupport.temporaryDirectory("review-commits")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        let git = GitClient(runner: FoundationProcessRunner())
        let base = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        let content = String(repeating: "large change\n", count: 30_000)
        try content.write(toFile: path + "/large.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "--", "large.txt"], in: path)
        try await TestSupport.runGit(["commit", "-m", "Add data\n\nExplain why this data is needed."], in: path)
        let head = try #require(await git.commitHash(of: "HEAD", worktreePath: path))
        try "uncommitted evidence".write(toFile: path + "/large.txt", atomically: true, encoding: .utf8)
        let context = try await git.reviewCommitContext(worktreePath: path, revisions: [head])
        #expect(context.contains(head))
        #expect(context.contains("Add data\n\nExplain why this data is needed."))
        #expect(context.contains("Initial commit") == false)
        #expect(try await git.reviewCommitContext(worktreePath: path, revisions: [base + ".." + head]) == context)
        #expect(try await git.reviewCommitContext(worktreePath: path, revisions: []).isEmpty)
        let snapshot = try await LocalReviewInput.snapshot(files: DiffParser.parse(git.commitDiff(
            worktreePath: path, commit: head,
        )))
        #expect(snapshot.utf8.count > LocalReviewInput.byteLimit)
        let prompt = try LocalReviewInput.prompt(
            instructions: "Review these changes.", snapshot: snapshot, commitContext: context,
        )
        #expect(prompt.contains("Explain why this data is needed."))
        #expect(prompt.contains("uncommitted evidence") == false)
        #expect(prompt.hasSuffix(snapshot))
    }
}
