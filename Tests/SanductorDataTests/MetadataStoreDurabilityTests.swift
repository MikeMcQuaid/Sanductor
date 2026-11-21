import Foundation
import SanductorData
import Testing

struct MetadataStoreDurabilityTests {
    @Test
    func `a failed write leaves memory unchanged so a later attempt retries`() throws {
        let root = try TestSupport.temporaryDirectory("store-failed-write")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let parent = root + "/parent"
        try "file blocks directory".write(toFile: parent, atomically: true, encoding: .utf8)
        let store = MetadataStore(file: parent + "/state.json")
        store.update { $0.prompts["task"] = "saved before launch" }
        #expect(store.load().prompts["task"] == nil)
        try FileManager.default.removeItem(atPath: parent)
        store.update { $0.prompts["task"] = "saved before launch" }
        #expect(FileManager.default.fileExists(atPath: parent + "/state.json"))
    }

    @Test
    func `a failed decode leaves private metadata intact on the next write`() throws {
        let file = try TestSupport.temporaryDirectory("store-invalid") + "/state.json"
        let data = Data(#"{"unrecognised":"keep","savedPrompts":"damaged"}"#.utf8)
        try data.write(to: URL(filePath: file))
        let store = MetadataStore(file: file)
        #expect(store.load().savedPrompts.isEmpty)
        #expect(throws: (any Error).self) { try store.updatePersisting { $0.prompts["session"] = "new" } }
        #expect(try Data(contentsOf: URL(filePath: file)) == data)
    }
}
