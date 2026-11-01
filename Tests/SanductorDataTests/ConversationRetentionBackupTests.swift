import Foundation
@testable import SanductorData
import Testing

// MARK: - ConversationRetentionBackupTests

struct ConversationRetentionBackupTests {
    // MARK: Internal

    @Test
    func `migration grace protects copies then honours compressed worktree indexes`() async throws {
        let root = try TestSupport.temporaryDirectory("retention-migration")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        let folder = root + "/.agentide-backup-test/conversations/session"
        try manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/tree", withIntermediateDirectories: true)
        try "gitdir: elsewhere".write(toFile: root + "/tree/.git", atomically: true, encoding: .utf8)
        let index = try JSONSerialization.data(withJSONObject: ["worktreePath": root + "/tree"])
        try index.write(to: URL(filePath: folder + "/conversation.json"))
        try await BackupCompression.write(
            source: folder + "/conversation.json", destination: folder + "/conversation.json.gz",
        )
        try manager.removeItem(atPath: folder + "/conversation.json")
        try "old transcript".write(toFile: folder + "/conversation.jsonl", atomically: true, encoding: .utf8)
        let now = Date()
        let later = now.addingTimeInterval(ConversationRetention.lifetime + 1)
        let service = service(root: root)
        #expect(await service.backupRetentionFiles(now: now).isEmpty)
        let files = await service.backupRetentionFiles(now: later)
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.expired(now: later, livePaths: [], openFiles: []) == false })
        try manager.removeItem(atPath: root + "/tree")
        #expect(files.allSatisfy { $0.expired(now: later, livePaths: [], openFiles: []) })
    }

    @Test(arguments: [false, true])
    func `maintenance deletes old unattributed backups only after a successful live check`(fails: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("retention-live-check")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/conversations/unknown", withIntermediateDirectories: true)
        let path = root + "/conversations/unknown/conversation.jsonl"
        try "old data".write(toFile: path, atomically: true, encoding: .utf8)
        let future = Date().addingTimeInterval(ConversationRetention.lifetime + 1)
        await service(root: root, fails: fails).expireConversations(now: future)
        #expect(manager.fileExists(atPath: path) == fails)
    }

    // MARK: Private

    private func service(root: String, fails: Bool = false) -> SessionService {
        let runner = RetentionRunner(fails: fails)
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root,
            sandboxHome: root + "/sandbox",
            metadataFile: root + "/state.json",
            appDirectory: root,
        )
        return SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: root),
            store: MetadataStore(file: root + "/state.json"),
            runners: [],
            processes: runner,
        )
    }
}

// MARK: - RetentionRunner

private struct RetentionRunner: ProcessRunner {
    let fails: Bool

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        ProcessResult(
            status: fails ? 1 : 0,
            standardOutput: arguments.contains("snapshot")
                ? #"{"result":{"snapshot":{"workspaces":[],"panes":[]}}}"# : "",
            standardError: "",
        )
    }
}
