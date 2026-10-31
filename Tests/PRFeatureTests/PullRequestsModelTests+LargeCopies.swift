import AppKit
@testable import PRFeature
import SanductorData
import Testing

extension PullRequestsModelTests {
    @Test
    func `large check copies keep all diagnostics in distinct files`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let store = MetadataStore(file: root + "/state.json")
        let model = makeModel(metadataFile: root + "/state.json")
        defer {
            for file in store.load().temporaryPromptFiles.keys {
                try? FileManager.default.removeItem(atPath: file)
            }
            try? FileManager.default.removeItem(atPath: root)
        }
        let log = "First error\n" + String(repeating: "middle diagnostic\n", count: 10_000) + "Last error"
        model.fetchFailedRunLog = { _ in log }
        let summary = summary(1, head: "feature", failingCheckLinks: ["https://github.com/o/r/actions/runs/1"])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(await model.copyFailingLogs(summary, pasteboard: pasteboard))
        let first = try #require(pasteboard.string(forType: .string))
        #expect(first.utf8.count < PromptPayload.inlineByteLimit)
        #expect(await model.copyFailingLogs(summary, pasteboard: pasteboard))
        #expect(pasteboard.string(forType: .string) != first)
        #expect(store.load().temporaryPromptFiles.count == 2)
        for file in store.load().temporaryPromptFiles.keys {
            #expect(try String(contentsOfFile: file, encoding: .utf8) == "## Run 1\n" + log)
        }
    }
}
