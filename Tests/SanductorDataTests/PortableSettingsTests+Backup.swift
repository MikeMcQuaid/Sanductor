import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension PortableSettingsTests {
    @Test
    func `a new Mac restores a linked private backup independently of the dotfile`() throws {
        let root = try TestSupport.temporaryDirectory("private-backup")
        let domain = "private-backup-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = FileManager.default
        let cloud = root + "/Personal Drive"
        try manager.createDirectory(atPath: cloud, withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/private", withIntermediateDirectories: true)
        let backup = cloud + "/private-settings.plist"
        let link = root + "/private/settings.plist"
        try manager.createSymbolicLink(atPath: link, withDestinationPath: backup)
        let legacyID = UUID()
        let dotfile = root + "/settings.plist"
        try Self.write([
            "promptSharingVersion": 2,
            "savedPrompts": [
                legacyID.uuidString: ["name": "From dotfiles", "prompt": "Earlier text"],
                UUID().uuidString: ["name": "Old memo", "prompt": "Keep this too"],
            ],
            "codeFontSize": 13,
        ], to: dotfile)
        var job = SavedPrompt(name: "Private job", prompt: "Review $TOKEN")
        job.schedule = PromptSchedule()
        job.repositoryPath = "/private/repository"
        var mode = WorkMode()
        mode.organisations = ["Private organisation"]
        try Self.write([
            "promptSharingVersion": 2,
            "savedPrompts": [
                legacyID.uuidString: ["name": "From backup", "prompt": "Latest text"],
                job.id.uuidString: PortableSettings.plist(job),
            ],
            "workMode": PortableSettings.plist(mode),
            FeedbackPrompt.localFix.key: "Private instructions",
        ], to: backup)
        let store = MetadataStore(file: root + "/state.json")
        let settings = try PortableSettings(file: dotfile, defaults: defaults, domain: domain)
        try settings.restorePrompts(in: store)
        let prompts = store.load().savedPrompts
        #expect(prompts.contains { $0.prompt == "Keep this too" })
        #expect(prompts.contains { $0.id == legacyID && $0.prompt == "Latest text" })
        let imported = try #require(prompts.first { $0.id == job.id })
        #expect(imported.schedule == job.schedule)
        #expect(imported.isEnabled == false)
        #expect(settings.restoredHostSettings[FeedbackPrompt.localFix.key] == "Private instructions")
        #expect(try JSONDecoder().decode(WorkMode.self, from: #require(defaults.data(forKey: "workMode"))) == mode)
        try settings.deletePrompt(id: legacyID)
        #expect(try manager.destinationOfSymbolicLink(atPath: link) == backup)
        #expect(try String(contentsOfFile: backup, encoding: .utf8).contains(legacyID.uuidString) == false)
        #expect(try String(contentsOfFile: dotfile, encoding: .utf8).contains("savedPrompts") == false)
    }

    @Test
    func `linking an existing backup merges prompts already saved on this Mac`() throws {
        let root = try TestSupport.temporaryDirectory("switch-backup")
        let domain = "switch-backup-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = MetadataStore(file: root + "/state.json")
        defaults.set("My review brief", forKey: FeedbackPrompt.localFix.key)
        let local = SavedPrompt(name: "Local", prompt: "Keep me")
        try store.updatePersisting { $0.savedPrompts = [local] }
        let dotfile = root + "/settings.plist"
        try PortableSettings(file: dotfile, defaults: defaults, domain: domain).restorePrompts(in: store)
        let cloud = root + "/Drive"
        let manager = FileManager.default
        try manager.createDirectory(atPath: cloud, withIntermediateDirectories: true)
        let backup = cloud + "/private-settings.plist"
        let uploaded = SavedPrompt(name: "Earlier Mac", prompt: "Also keep me")
        try Self.write([
            "promptSharingVersion": 2, "savedPrompts": [uploaded.id.uuidString: PortableSettings.plist(uploaded)],
        ], to: backup)
        let link = root + "/private/settings.plist"
        try manager.removeItem(atPath: link)
        try manager.createSymbolicLink(atPath: link, withDestinationPath: backup)
        try PortableSettings(file: dotfile, defaults: defaults, domain: domain).restorePrompts(in: store)
        #expect(Set(store.load().savedPrompts.map(\.id)) == [local.id, uploaded.id])
        #expect(try String(contentsOfFile: backup, encoding: .utf8).contains("My review brief"))
        #expect(try String(contentsOfFile: backup, encoding: .utf8).contains(local.id.uuidString))
    }

    @Test
    func `failed migration leaves the old combined file intact for retry`() throws {
        let root = try TestSupport.temporaryDirectory("backup-retry")
        let domain = "backup-retry-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let dotfile = root + "/settings.plist"
        let id = UUID()
        let legacy = ["savedPrompts": [id.uuidString: ["name": "Only copy", "prompt": "Recover me"]]]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0)
        try data.write(to: URL(filePath: dotfile))
        let backup = URL(filePath: root + "/private/settings.plist")
        try FileManager.default.createDirectory(atPath: root + "/private", withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: backup)
        #expect(throws: (any Error).self) { try PortableSettings(file: dotfile, defaults: defaults, domain: domain) }
        #expect(try Data(contentsOf: URL(filePath: dotfile)) == data)
        try FileManager.default.removeItem(at: backup)
        let settings = try PortableSettings(file: dotfile, defaults: defaults, domain: domain)
        let store = MetadataStore(file: root + "/state.json")
        try settings.restorePrompts(in: store)
        #expect(store.load().savedPrompts.first?.prompt == "Recover me")
        #expect(try String(contentsOf: backup, encoding: .utf8).contains(id.uuidString))
    }
}
