import Foundation
@testable import SanductorData
import Testing

struct ConversationRetentionTests {
    @Test
    func `expiry protects worktrees and live sessions but not main checkouts`() throws {
        let root = try TestSupport.temporaryDirectory("retention")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/main/.git", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/tree", withIntermediateDirectories: true)
        try "gitdir: elsewhere".write(toFile: root + "/tree/.git", atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let old = now.addingTimeInterval(-31 * 86_400)
        for (name, cwd, protected) in [
            ("main", root + "/main", false), ("tree", root + "/tree", true),
            ("deleted", root + "/gone", false), ("unknown", "", false),
            ("live", root + "/live", true), ("same-name", root + "/gone/live", false),
        ] {
            let path = root + "/" + name + ".jsonl"
            try "data".write(toFile: path, atomically: true, encoding: .utf8)
            try manager.setAttributes([.modificationDate: old], ofItemAtPath: path)
            let file = try #require(ConversationRetention.File(path: path, worktree: cwd))
            #expect(file.expired(now: now, livePaths: [root + "/live"], openFiles: []) == !protected)
            #expect(file.expired(now: now, livePaths: [], openFiles: [path]) == false)
        }
    }

    @Test
    func `recent files and changed candidates survive expiry`() throws {
        let root = try TestSupport.temporaryDirectory("retention-age")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/conversation.jsonl"
        try "data".write(toFile: path, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
        let file = try #require(ConversationRetention.File(path: path, worktree: nil))
        #expect(file.expired(
            now: now.addingTimeInterval(ConversationRetention.lifetime), livePaths: [], openFiles: [],
        ) == false)
        #expect(file.expired(now: now, livePaths: [], openFiles: []) == false)
        #expect(file.expired(now: now.addingTimeInterval(31 * 86_400), livePaths: [], openFiles: []))
        try "new data".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(file.unchanged == false)
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: path)
        #expect(ConversationRetention.File(path: root + "/link", worktree: nil) == nil)
    }
}
