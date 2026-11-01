import Foundation
@testable import SanductorData
import Testing

struct BackupCompressionTests {
    // MARK: Internal

    @Test
    func `existing backups shrink without touching originals or following links`() async throws {
        let root = try TestSupport.temporaryDirectory("compression")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        let text = String(repeating: "a transcript line\n", count: 10_000)
        let files = ["conversations/session/conversation.jsonl", ".agentide-backup-test/conversations/session.jsonl"]
        for file in files + ["source.jsonl", "conversations/session/conversation.json"] {
            let path = URL(filePath: root + "/" + file)
            try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: path, atomically: true, encoding: .utf8)
        }
        try manager.createSymbolicLink(
            atPath: root + "/conversations/linked", withDestinationPath: root + "/source.jsonl",
        )
        let runner = FoundationProcessRunner()
        let service = service(root: root)
        await service.compressConversationBackups()
        for file in files {
            let compressed = root + "/" + file + ".gz"
            #expect(manager.fileExists(atPath: root + "/" + file) == false)
            let result = try await runner.run(
                ["/usr/bin/gzip", "-cd", compressed], workingDirectory: nil, environment: [:],
            )
            #expect(result.succeeded)
            #expect(result.standardOutput == text)
            let size = try #require(manager.attributesOfItem(atPath: compressed)[.size] as? Int)
            #expect(size < text.utf8.count)
        }
        #expect(try String(contentsOfFile: root + "/source.jsonl", encoding: .utf8) == text)
        #expect(manager.fileExists(atPath: root + "/conversations/linked.gz") == false)
        #expect(manager.fileExists(atPath: root + "/conversations/session/conversation.json"))
        let before = try Data(contentsOf: URL(filePath: root + "/" + files[0] + ".gz"))
        await service.compressConversationBackups()
        #expect(try Data(contentsOf: URL(filePath: root + "/" + files[0] + ".gz")) == before)
    }

    @Test
    func `maintenance removes abandoned compression output but keeps recent writes`() async throws {
        let root = try TestSupport.temporaryDirectory("compression-scratch")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/conversations", withIntermediateDirectories: true)
        let interrupted = root + "/conversations/old.gz.compression-" + UUID().uuidString
        let recent = root + "/conversations/new.gz.compression-" + UUID().uuidString
        for path in [interrupted, recent] {
            try "partial".write(toFile: path, atomically: true, encoding: .utf8)
        }
        try manager.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: interrupted,
        )
        await service(root: root).compressConversationBackups()
        #expect(manager.fileExists(atPath: interrupted) == false)
        #expect(manager.fileExists(atPath: recent))
    }

    @Test
    func `failed publication preserves the source and removes temporary output`() async throws {
        let root = try TestSupport.temporaryDirectory("compression-failure")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let source = root + "/source.jsonl"
        try "original".write(toFile: source, atomically: true, encoding: .utf8)
        let destination = root + "/occupied.gz"
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) {
            try await BackupCompression.write(source: source, destination: destination)
        }
        #expect(try String(contentsOfFile: source, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root).sorted() == ["occupied.gz", "source.jsonl"])
    }

    // MARK: Private

    private func service(root: String) -> SessionService {
        let runner = FoundationProcessRunner()
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root + "/shared",
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
        )
    }
}
