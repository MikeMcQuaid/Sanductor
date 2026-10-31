import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct PromptPayloadTests {
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
        PromptPayload.clean(paths: world.paths, store: store, sessions: [])
        #expect(store.load().temporaryPromptFiles.count == 2)
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], now: .distantFuture)
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
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], now: .distantFuture)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.paths.promptsDirectory) == ["notes.md"])
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
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], now: .distantFuture)
        #expect(store.load().temporaryPromptFiles.count == 2)
        store.update { $0.pullRequestAutomation["pr"]?.attempt = nil }
        PromptPayload.clean(
            paths: world.paths,
            store: store,
            sessions: [
                AgentSession(name: "agent", agent: .codexCLI, status: .running, paneID: "pane", activity: .working),
            ],
            now: .distantFuture,
        )
        #expect(store.load().temporaryPromptFiles.count == 2)
        PromptPayload.clean(paths: world.paths, store: store, sessions: [], now: .distantFuture)
        #expect(store.load().temporaryPromptFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: result) == false)
    }
}
