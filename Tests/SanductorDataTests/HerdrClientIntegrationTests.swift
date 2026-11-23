import Foundation
@testable import SanductorData
import SanductorDomain
import Synchronization
import Testing

/// Exercises the herdr adapter against a real server on a private
/// config home: workspace lifecycle, working directories, finished
/// detection and typed text.
struct HerdrClientIntegrationTests {
    @Test
    func `sessions start in their directory and die visibly`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("pane")
        defer { TestSupport.stopServerSync(configHome: home) }

        try await herdr.newSession(name: "sanductor--r--b--claude", directory: directory, command: "sleep 20")
        let running = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.sessionName == "sanductor--r--b--claude" && $0.isFinished == false }
        }
        #expect(running)
        let pane = try #require(try await herdr.panes().first)
        #expect(pane.currentPath == directory)
        #expect(pane.paneID.isEmpty == false)

        try await herdr.killSession(name: "sanductor--r--b--claude")
        let gone = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.isEmpty
        }
        #expect(gone)
    }

    @Test
    func `a finished agent leaves its shell back at a prompt`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("dead")
        defer { TestSupport.stopServerSync(configHome: home) }

        try await herdr.newSession(name: "sanductor--r--dead--claude", directory: directory, command: "true")
        let finished = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.contains { $0.sessionName == "sanductor--r--dead--claude" && $0.isFinished }
        }
        #expect(finished)
    }

    @Test
    func `a repeated label makes a second workspace and one kill closes both`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("fresh")
        defer { TestSupport.stopServerSync(configHome: home) }

        // Labels are not unique to herdr, which is why every fresh
        // start kills the label first; a kill closing every holder
        // is what keeps a raced duplicate from surviving it.
        try await herdr.newSession(name: "sanductor--r--fresh--codex", directory: directory, command: "sleep 20")
        try await herdr.newSession(name: "sanductor--r--fresh--codex", directory: directory, command: "sleep 20")
        let both = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            let matching = panes.count { $0.sessionName == "sanductor--r--fresh--codex" }
            return matching == 2
        }
        #expect(both)

        try await herdr.killSession(name: "sanductor--r--fresh--codex")
        let gone = await TestSupport.poll {
            let panes = await (try? herdr.panes()) ?? []
            return panes.isEmpty
        }
        #expect(gone)
    }

    @Test
    func `a slow drop pastes its staged paths before later input even when a file fails`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let output = world.root + "/typed.txt"
        try await world.herdr.newSession(
            name: "sanductor--r--type--claude", directory: world.root, command: "command cat > typed.txt",
        )
        try #require(await TestSupport.poll { FileManager.default.fileExists(atPath: output) })
        let pane = try #require(try await world.herdr.panes().first)
        let channel = HerdrTerminalChannel(command: world.herdr.attachCommand(paneID: pane.paneID))
        _ = try await channel.start()
        channel.send(HerdrTerminal.resizeCommand(columns: 80, rows: 24))
        let gate = DispatchSemaphore(value: 0)
        let reported = Mutex(false)
        channel.send(HerdrTerminal.inputCommand(bytes: "first: ".utf8))
        channel.attach([
            .image(Data([1]), named: "first.png"), .file(URL(fileURLWithPath: world.root + "/missing")),
            .image(Data(), named: "skipped.png"),
        ], staging: { attachment in
            #expect(Thread.isMainThread == false)
            if case .image = attachment {
                try #require(gate.wait(timeout: .now() + 10) == .success)
            }
            return try world.service.stageDroppedFile(attachment)
        }, onError: { _ in reported.withLock { $0 = true } })
        channel.send(HerdrTerminal.inputCommand(bytes: "\rsecond: ".utf8))
        channel.attach([.image(Data([2]), named: "second.png")], staging: world.service.stageDroppedFile) { error in
            Issue.record(error)
        }
        channel.send(HerdrTerminal.inputCommand(bytes: "\r".utf8))
        gate.signal()

        let delivered = await TestSupport.poll {
            (try? String(contentsOfFile: output, encoding: .utf8))?.hasSuffix("second.png \n") == true
                && reported.withLock { $0 }
        }
        await channel.stop()
        try #require(delivered)
        let staged = world.service.store.load().temporaryPromptFiles.keys
        #expect(staged.count == 2)
        let first = try #require(staged.first { $0.hasSuffix("-first.png") })
        let second = try #require(staged.first { $0.hasSuffix("-second.png") })
        #expect(try String(contentsOfFile: output, encoding: .utf8) == "first: \(first) \nsecond: \(second) \n")
    }
}
