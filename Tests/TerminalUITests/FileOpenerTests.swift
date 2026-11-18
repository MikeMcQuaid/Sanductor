import Foundation
import SanductorData
@testable import TerminalUI
import Testing

struct FileOpenerTests {
    @Test
    func `repository paths cannot become absolute editor requests`() {
        #expect(FileOpener.safePath(relativePath: "/outside/file", worktreePath: "/repo") == nil)
        #expect(FileOpener.safePath(relativePath: "../outside/file", worktreePath: "/repo") == nil)
        #expect(FileOpener.safePath(relativePath: "Sources/file.swift", worktreePath: "/repo")
            == "/repo/Sources/file.swift")
    }

    @Test
    func `the external editor runs only when Settings names a command`() {
        let saved = UserDefaults.standard.object(forKey: AppSettings.externalEditorKey)
        defer { UserDefaults.standard.set(saved, forKey: AppSettings.externalEditorKey) }
        UserDefaults.standard.set("  ", forKey: AppSettings.externalEditorKey)
        #expect(FileOpener.openInExternalEditor("/repo") == false)
        UserDefaults.standard.set("true", forKey: AppSettings.externalEditorKey)
        #expect(FileOpener.openInExternalEditor("/repo"))
        #expect(FileOpener.openInExternalEditor("/repo", "/repo/Sources/file.swift"))
    }

    @Test
    func `a file from a worktree not on screen opens there by its absolute path`() {
        let keys = ["editorFilePath", "editorFileLine", "editorFileWorktree", "editorFileRequest"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        FileOpener.open(relativePath: "Sources/file.swift", line: 3, worktreePath: "/holder", showingIn: "/shown")
        #expect(UserDefaults.standard.string(forKey: "editorFilePath") == "/holder/Sources/file.swift")
        #expect(UserDefaults.standard.string(forKey: "editorFileWorktree") == "/shown")
        FileOpener.open(relativePath: "Sources/file.swift", line: 3, worktreePath: "/shown", showingIn: "/shown")
        #expect(UserDefaults.standard.string(forKey: "editorFilePath") == "Sources/file.swift")
        #expect(UserDefaults.standard.string(forKey: "editorFileWorktree") == "/shown")
    }
}
