import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct PromptPayloadTests {
    // MARK: Internal

    @Test
    func `oversized feedback uses unique complete files and small pastes stay inline`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        #expect(try PromptPayload.prepare("short review", paths: world.paths, store: store) == "short review")
        #expect(store.load().temporaryPromptFiles.isEmpty)
        let text = "first\n" + String(repeating: "é", count: PromptPayload.inlineByteLimit) + "\nlast"
        let first = try PromptPayload.prepare(text, paths: world.paths, store: store)
        let second = try PromptPayload.prepare(text, paths: world.paths, store: store)
        #expect(first != second)
        let files = store.load().temporaryPromptFiles
        #expect(files.count == 2)
        for file in files.keys {
            #expect(try String(contentsOfFile: file, encoding: .utf8) == text)
        }
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [])
        #expect(store.load().temporaryPromptFiles.count == 2)
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: Date().addingTimeInterval(Self.day),
        )
        #expect(store.load().temporaryPromptFiles.isEmpty)
        #expect(files.keys.allSatisfy { FileManager.default.fileExists(atPath: $0) == false })
    }

    @Test
    func `setup adopts old owned files without touching unrelated files`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        try FileManager.default.createDirectory(atPath: world.paths.promptsDirectory, withIntermediateDirectories: true)
        store.update { $0.prompts["old-session"] = "initial prompt" }
        for name in ["old-session.md", "autofix-old.json", "notes.md"] {
            try "content".write(toFile: world.paths.promptsDirectory + "/" + name, atomically: true, encoding: .utf8)
        }
        try PromptPayload.adoptExisting(paths: world.paths, store: store)
        #expect(store.load().temporaryPromptFiles.count == 2)
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: .distantFuture)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.paths.promptsDirectory) == ["notes.md"])
    }

    @Test
    func `dropped attachments expire a day after staging rather than their source modification`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let source = world.root + "/screenshot.png"
        try "image".write(toFile: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: source)
        let dropped = try world.service.stageDroppedFile(at: URL(fileURLWithPath: source))
        let created = try #require(store.load().temporaryPromptFiles[dropped]?.createdAt)
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: created.addingTimeInterval(Self.day - 1),
        )
        #expect(FileManager.default.fileExists(atPath: dropped))
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: created.addingTimeInterval(Self.day),
        )
        #expect(FileManager.default.fileExists(atPath: dropped) == false)
        #expect(store.load().temporaryPromptFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: source))
    }

    @Test
    func `setup adopts staged attachments and preserves unrelated files and symlinks`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let directory = world.paths.sharedWorkspace + "/tmp"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let dropped = "drop-" + UUID().uuidString + "-screenshot.png"
        for name in [dropped, "notes.md", "drop-not-an-attachment.png"] {
            try "content".write(toFile: directory + "/" + name, atomically: true, encoding: .utf8)
        }
        let link = "drop-" + UUID().uuidString + "-link.png"
        try FileManager.default.createSymbolicLink(atPath: directory + "/" + link, withDestinationPath: "notes.md")
        let folder = directory + "/drop-" + UUID().uuidString + "-folder"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try "content".write(toFile: folder + "/attachment.txt", atomically: true, encoding: .utf8)
        try PromptPayload.adoptExisting(paths: world.paths, store: store)
        #expect(Set(store.load().temporaryPromptFiles.keys) == [directory + "/" + dropped, folder])
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: Date().addingTimeInterval(Self.day),
        )
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: directory))
            == ["notes.md", "drop-not-an-attachment.png", link])
    }

    @Test
    func `cleanup refuses a temporary directory replaced by a symlink`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let source = world.root + "/attachment.txt"
        try "content".write(toFile: source, atomically: true, encoding: .utf8)
        let dropped = try world.service.stageDroppedFile(at: URL(fileURLWithPath: source))
        let directory = world.paths.sharedWorkspace + "/tmp"
        let moved = world.root + "/preserved"
        try FileManager.default.moveItem(atPath: directory, toPath: moved)
        try FileManager.default.createSymbolicLink(atPath: directory, withDestinationPath: moved)
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: Date().addingTimeInterval(Self.day),
        )
        #expect(FileManager.default.fileExists(atPath: dropped))
        #expect(store.load().temporaryPromptFiles[dropped] != nil)
    }

    @Test(arguments: [false, true])
    func `adopted directories protect edits before or after adoption`(editAfterAdoption: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let now = Date()
        let old = now.addingTimeInterval(-2 * Self.day)
        let folder = world.paths.sharedWorkspace + "/tmp/drop-" + UUID().uuidString + "-folder"
        let file = folder + "/nested/attachment.txt"
        try FileManager.default.createDirectory(atPath: folder + "/nested", withIntermediateDirectories: true)
        try "recent work".write(toFile: file, atomically: true, encoding: .utf8)
        for path in [folder, folder + "/nested", file] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
        }
        if editAfterAdoption == false {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file)
        }
        try PromptPayload.adoptExisting(paths: world.paths, store: store)
        if editAfterAdoption {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file)
        }
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: now)
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "recent work")
        #expect(store.load().temporaryPromptFiles[folder] != nil)

        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [],
            protectedPaths: [],
            now: now.addingTimeInterval(Self.day + 1),
        )
        #expect(FileManager.default.fileExists(atPath: folder) == false)
        #expect(store.load().temporaryPromptFiles[folder] == nil)
    }

    @Test
    func `cleanup retains active and working prompt files then removes completed inputs and results`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let attempt = AutofixAttempt(
            id: "attempt",
            sources: [.checks],
            head: "head",
            remoteHead: "head",
            localThreadIDs: [],
            branch: "branch",
            worktreePath: world.repository.path,
            sessionName: "agent",
            paneID: "pane",
            threads: [:],
        )
        _ = try PromptPayload.prepare(
            String(repeating: "x", count: PromptPayload.inlineByteLimit + 1),
            paths: world.paths,
            store: store,
            attempt: attempt,
        )
        let result = world.paths.promptsDirectory + "/autofix-attempt.json"
        try "result".write(toFile: result, atomically: true, encoding: .utf8)
        try PromptPayload.track(result, store: store, attempt: attempt)
        store.update { metadata in
            var state = PullRequestAutomation(repositoryPath: world.repository.path, number: 1, url: "pr")
            state.attempt = attempt
            metadata.pullRequestAutomation["pr"] = state
        }
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: .distantFuture)
        #expect(store.load().temporaryPromptFiles.count == 2)
        store.update { $0.pullRequestAutomation["pr"]?.attempt = nil }
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [
                AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .working),
            ],
            protectedPaths: [],
            now: .distantFuture,
        )
        #expect(store.load().temporaryPromptFiles.count == 2)
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: .distantFuture)
        #expect(store.load().temporaryPromptFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: result) == false)
    }

    // MARK: Private

    private static let day: TimeInterval = 86_400
}
