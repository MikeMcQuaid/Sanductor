import AppKit
import SanductorData
@testable import TerminalUI
import Testing

@MainActor
struct TerminalResizeTests {
    @Test
    func `a run of size changes reaches herdr as the last size alone`() async throws {
        let record = URL(filePath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-scratch/resizes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: record) }
        try FileManager.default.createDirectory(
            at: record.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        defer { coordinator.tearDown() }
        // The client's standard input is what herdr would be told.
        let channel = HerdrTerminalChannel(command: ["tee", record.path])
        _ = try await channel.start()
        coordinator.view = view
        coordinator.channel = channel
        for columns in [100, 90, 80] {
            coordinator.sizeChanged(source: view, newCols: columns, newRows: 24)
        }

        var sent = [Substring]()
        let deadline = ContinuousClock.now + .seconds(5)
        while sent.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            sent = ((try? String(contentsOf: record, encoding: .utf8)) ?? "").split(separator: "\n")
        }
        // Anything else on its way has landed by now.
        try await Task.sleep(for: .milliseconds(300))
        sent = ((try? String(contentsOf: record, encoding: .utf8)) ?? "").split(separator: "\n")
        #expect(sent.count == 1)
        #expect(sent.last?.contains("\"cols\":80") == true)
    }

    @Test
    func `a size still settling is forgotten when its client is discarded`() async throws {
        let record = URL(filePath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-scratch/resizes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: record) }
        try FileManager.default.createDirectory(
            at: record.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        defer { coordinator.tearDown() }
        // Appending, since the discarded client may spawn late and a
        // truncating open would erase what its replacement wrote.
        coordinator.startWhenSized(.control(command: ["tee", "-a", record.path]), in: view)
        coordinator.sizeChanged(source: view, newCols: 100, newRows: 24)
        coordinator.reattach(in: view)

        // The replacement sends the view's own size as it attaches.
        var sent = ""
        let deadline = ContinuousClock.now + .seconds(5)
        while sent.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            sent = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
        }
        // Anything stale has landed by now.
        try await Task.sleep(for: .milliseconds(300))
        sent = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
        #expect(sent.isEmpty == false)
        #expect(sent.contains("\"cols\":100") == false)
    }
}
