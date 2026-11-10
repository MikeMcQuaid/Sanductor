import Foundation
@testable import SanductorData
import Testing

// MARK: - ConversationRetentionBackupTests

struct ConversationRetentionBackupTests {
    // MARK: Internal

    @Test(arguments: [false, true])
    func `attachment cleanup skips fresh files and throttles failed live checks`(expired: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("attachment-cadence")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let service = service(root: root, fails: true)
        let file = root + "/tmp/drop-" + UUID().uuidString + "-file.txt"
        try FileManager.default.createDirectory(atPath: root + "/tmp", withIntermediateDirectories: true)
        try "attachment".write(toFile: file, atomically: true, encoding: .utf8)
        if expired {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-2 * 86_400)], ofItemAtPath: file,
            )
        }
        try PromptPayload.adoptExisting(paths: service.paths, store: service.store)
        let runner = try #require(service.processes as? RetentionRunner)
        _ = await service.refreshPullRequestAutomation(groups: [])
        await service.feedbackCollector.wait("autofix")
        await service.feedbackCollector.wait("prompt-cleanup")
        let calls = await runner.calls
        #expect((calls > 0) == expired)
        _ = await service.refreshPullRequestAutomation(groups: [])
        await service.feedbackCollector.wait("autofix")
        await service.feedbackCollector.wait("prompt-cleanup")
        #expect(await runner.calls == calls)
        #expect(FileManager.default.fileExists(atPath: file))
    }

    @Test(arguments: ["open", "cwd", "pane", "failed-panes", "failed-open", "none"])
    func `dashboard cleanup protects tracked attachments using fresh live state`(protection: String) async throws {
        let root = try TestSupport.temporaryDirectory("attachment-live")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = WorkspacePaths(
            hostUser: "test", sharedWorkspace: root, sandboxHome: root + "/sandbox", metadataFile: root + "/state.json",
        )
        let store = MetadataStore(file: paths.metadataFile)
        let file = root + "/tmp/drop-" + UUID().uuidString + "-file.txt"
        let folder = root + "/tmp/drop-" + UUID().uuidString + "-folder"
        try FileManager.default.createDirectory(atPath: folder + "/nested", withIntermediateDirectories: true)
        for path in [file, folder + "/nested/input.txt", folder + "-other"] {
            try "attachment".write(toFile: path, atomically: true, encoding: .utf8)
        }
        for path in [file, folder, folder + "/nested", folder + "/nested/input.txt", folder + "-other"] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-2 * 86_400)], ofItemAtPath: path,
            )
        }
        try PromptPayload.adoptExisting(paths: paths, store: store)
        let service = service(root: root, openFiles: [file, folder + "/nested/input.txt"], protection: protection)
        _ = await service.refreshPullRequestAutomation(groups: [])
        await service.feedbackCollector.wait("autofix")
        await service.feedbackCollector.wait("prompt-cleanup")
        #expect(FileManager.default.fileExists(atPath: folder + "/nested/input.txt") == (protection != "none"))
        #expect(FileManager.default.fileExists(atPath: file)
            == ["open", "failed-panes", "failed-open"].contains(protection))
        #expect(FileManager.default.fileExists(atPath: folder + "-other") == protection.hasPrefix("failed-"))
        #expect((store.load().temporaryPromptFiles[folder] != nil) == (protection != "none"))

        let closed = self.service(root: root)
        _ = await closed.refreshPullRequestAutomation(groups: [])
        await closed.feedbackCollector.wait("autofix")
        await closed.feedbackCollector.wait("prompt-cleanup")
        #expect(FileManager.default.fileExists(atPath: folder) == false)
        #expect(FileManager.default.fileExists(atPath: file) == false)
        #expect(store.load().temporaryPromptFiles.isEmpty)
    }

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
        try manager.createDirectory(atPath: root + "/tmp", withIntermediateDirectories: true)
        let temporary = root + "/tmp/build.log"
        try "old log".write(toFile: temporary, atomically: true, encoding: .utf8)
        let future = Date().addingTimeInterval(ConversationRetention.lifetime + 1)
        await service(root: root, fails: fails).expireConversations(now: future)
        #expect(manager.fileExists(atPath: path) == fails)
        #expect(manager.fileExists(atPath: temporary) == fails)
    }

    @Test
    func `temporary cleanup expires files and complete trees after seven days`() async throws {
        let root = try TestSupport.temporaryDirectory("temporary-expiry")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        for name in ["tmp/old/cache", "tmp/recent/cache", "tmp/sanductor", "sanductor/prompts"] {
            try manager.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
        }
        for name in [
            "tmp/build.log", "tmp/boundary.log", "tmp/recent.log", "tmp/old/cache/data",
            "tmp/recent/cache/data", "tmp/recent/old-data", "tmp/sanductor/performance-log",
            "tmp/sanductor/messages.log", "tmp/sanductor/performance.log", "sanductor/prompts/agentide-session.md",
        ] {
            try "data".write(toFile: root + "/" + name, atomically: true, encoding: .utf8)
            try manager.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-1)], ofItemAtPath: root + "/" + name,
            )
        }
        for name in ["tmp/old/cache", "tmp/old", "tmp/recent/cache", "tmp/recent"] {
            try manager.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-1)], ofItemAtPath: root + "/" + name,
            )
        }
        try manager.setAttributes([.modificationDate: cutoff], ofItemAtPath: root + "/tmp/boundary.log")
        for name in ["tmp/recent.log", "tmp/recent/cache/data", "tmp/sanductor/performance.log"] {
            try manager.setAttributes([.modificationDate: now], ofItemAtPath: root + "/" + name)
        }
        await service(root: root).expireConversations(now: now)
        for name in [
            "tmp/build.log", "tmp/old", "tmp/recent/old-data", "tmp/sanductor/messages.log",
            "sanductor/prompts/agentide-session.md",
        ] {
            #expect(manager.fileExists(atPath: root + "/" + name) == false)
        }
        for name in [
            "tmp/boundary.log", "tmp/recent.log", "tmp/recent/cache/data",
            "tmp/sanductor/performance-log", "tmp/sanductor/performance.log",
        ] {
            #expect(manager.fileExists(atPath: root + "/" + name))
        }
    }

    @Test
    func `temporary cleanup retains opened trees and tracked feedback`() async throws {
        let root = try TestSupport.temporaryDirectory("temporary-live")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        let now = Date().addingTimeInterval(8 * 86_400)
        try manager.createDirectory(atPath: root + "/tmp/in-use", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/sanductor/prompts", withIntermediateDirectories: true)
        for name in ["tmp/open.log", "tmp/in-use/dependency", "tmp/tracked", "sanductor/prompts/prompt-active.md"] {
            try "data".write(toFile: root + "/" + name, atomically: true, encoding: .utf8)
        }
        let store = MetadataStore(file: root + "/state.json")
        for name in ["tmp/tracked", "sanductor/prompts/prompt-active.md"] {
            try PromptPayload.track(root + "/" + name, store: store, attempt: nil)
        }
        await service(root: root, openFiles: [root + "/tmp/open.log", root + "/tmp/in-use/dependency"])
            .expireConversations(now: now)
        for name in ["tmp/open.log", "tmp/in-use/dependency", "tmp/tracked", "sanductor/prompts/prompt-active.md"] {
            #expect(manager.fileExists(atPath: root + "/" + name))
        }
    }

    @Test
    func `temporary cleanup never follows linked roots or descendants`() async throws {
        let root = try TestSupport.temporaryDirectory("temporary-links")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/outside/sanductor", withIntermediateDirectories: true)
        try "data".write(toFile: root + "/outside/sanductor/keep", atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(atPath: root + "/tmp", withDestinationPath: root + "/outside")
        let future = Date().addingTimeInterval(8 * 86_400)
        await service(root: root).expireConversations(now: future)
        #expect(manager.fileExists(atPath: root + "/outside/sanductor/keep"))
        try manager.removeItem(atPath: root + "/tmp")
        try manager.createDirectory(atPath: root + "/tmp/old", withIntermediateDirectories: true)
        try manager.createSymbolicLink(atPath: root + "/tmp/old/link", withDestinationPath: root + "/outside")
        await service(root: root).expireConversations(now: future)
        #expect(manager.fileExists(atPath: root + "/tmp/old") == false)
        #expect(manager.fileExists(atPath: root + "/outside/sanductor/keep"))
    }

    // MARK: Private

    private func service(
        root: String, fails: Bool = false, openFiles: [String] = [], protection: String = "open",
    ) -> SessionService {
        let runner = RetentionRunner(fails: fails, openFiles: openFiles, protection: protection)
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

private actor RetentionRunner: ProcessRunner {
    // MARK: Lifecycle

    init(fails: Bool, openFiles: [String], protection: String) {
        self.fails = fails
        self.openFiles = openFiles
        self.protection = protection
    }

    // MARK: Internal

    let fails: Bool
    let openFiles: [String]
    let protection: String
    private(set) var calls = 0

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        calls += 1
        let snapshot = arguments.contains("snapshot")
        let directory = openFiles.last.map { URL(filePath: $0).deletingLastPathComponent().path } ?? "/"
        var output = #"{"result":{"snapshot":{"workspaces":[],"panes":[]}}}"#
        if snapshot, protection == "pane" {
            output = #"""
            {"result":{"snapshot":{"workspaces":[{"workspace_id":"workspace","label":"agent"}],
            "panes":[{"pane_id":"pane","workspace_id":"workspace","cwd":"\#(directory)"}]}}}
            """#
        } else if snapshot == false {
            output = protection == "cwd" ? "fcwd\nn" + directory
                : protection == "open" ? openFiles.lazy.map { "n" + $0 }.joined(separator: "\n") : ""
        }
        return ProcessResult(
            status: fails || protection == (snapshot ? "failed-panes" : "failed-open") ? 1 : 0,
            standardOutput: output,
            standardError: "",
        )
    }
}
