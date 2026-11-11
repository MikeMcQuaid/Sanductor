import Foundation
@testable import SanductorData
import Testing

/// Exercises hook installation against a temporary template
/// directory: idempotency and coexistence with third-party hooks.
struct HookInstallerTests {
    @Test
    func `unreadable temporary files do not prevent hook installation`() throws {
        let root = try TestSupport.temporaryDirectory("unreadable-hooks")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = WorkspacePaths(
            hostUser: "test", sharedWorkspace: root, sandboxHome: root + "/home", metadataFile: root + "/state.json",
        )
        try FileManager.default.createDirectory(atPath: root + "/tmp", withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root + "/tmp")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root + "/tmp") }
        #expect(throws: (any Error).self) {
            try FileManager.default.contentsOfDirectory(atPath: root + "/tmp")
        }
        try FileManager.default.createDirectory(atPath: paths.promptsDirectory, withIntermediateDirectories: true)
        let prompt = paths.promptsDirectory + "/prompt-old.md"
        try "feedback".write(toFile: prompt, atomically: true, encoding: .utf8)

        try HookInstaller(paths: paths).ensureInstalled()

        let directory = paths.userTemplateDirectory + "/.claude"
        #expect(FileManager.default.isExecutableFile(atPath: directory + "/sanductor-notify.sh"))
        let settings = try String(contentsOfFile: directory + "/settings.json", encoding: .utf8)
        #expect(settings.contains("sanductor-notify.sh"))
        #expect(MetadataStore(file: paths.metadataFile).load().temporaryPromptFiles[prompt] != nil)
    }

    @Test
    func `legacy hook commands and session variables still deliver events`() async throws {
        let root = try TestSupport.temporaryDirectory("legacy-hooks")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = WorkspacePaths(
            hostUser: "test", sharedWorkspace: root, sandboxHome: root + "/home", metadataFile: root + "/state.json",
        )
        let installer = HookInstaller(paths: paths)
        try installer.ensureInstalled()
        let session = "agentide--repo--branch--claude"
        let result = try await FoundationProcessRunner().run(
            [
                "/usr/bin/env", "-u", "SANDUCTOR_SESSION", "AGENTIDE_SESSION=" + session,
                paths.userTemplateDirectory + "/.claude/agentide-notify.sh", "Stop",
            ],
            workingDirectory: root,
            environment: ["SHARED_WORKSPACE": root],
        )
        #expect(result.succeeded)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("agentide-notify.sh is deprecated"))
        #expect(result.standardError.contains("AGENTIDE_SESSION is deprecated"))
        let events = try String(contentsOfFile: paths.eventsDirectory + "/" + session + ".jsonl", encoding: .utf8)
        #expect(events.contains("\"event\":\"Stop\""))
    }

    @Test
    func `installs alongside existing hooks exactly once`() throws {
        let root = try TestSupport.temporaryDirectory("hooks")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root,
            sandboxHome: root + "/home",
            metadataFile: root + "/state.json",
        )
        let settingsPath = paths.userTemplateDirectory + "/.claude/settings.json"
        try FileManager.default.createDirectory(
            atPath: paths.userTemplateDirectory + "/.claude",
            withIntermediateDirectories: true,
        )
        let existing = """
        {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "third-party-notify"}]}]}}
        """
        try existing.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let installer = HookInstaller(paths: paths)
        try installer.ensureInstalled()
        try installer.ensureInstalled()

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        for event in HookInstaller.events {
            let entries = try #require(hooks[event] as? [[String: Any]], "missing \(event)")
            let commands = entries.flatMap { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
            let installed = commands.count { $0.contains("sanductor-notify") }
            #expect(installed == 1)
            if event == "Stop" {
                #expect(commands.contains("third-party-notify"))
            }
        }

        let script = paths.userTemplateDirectory + "/.claude/sanductor-notify.sh"
        #expect(FileManager.default.isExecutableFile(atPath: script))
    }
}
