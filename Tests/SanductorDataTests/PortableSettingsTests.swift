import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

@MainActor
struct PortableSettingsTests {
    static func write(_ values: [String: Any], to path: String) throws {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: URL(filePath: path))
    }

    @Test
    func `backfill runs after the rename and preserves existing choices and explicit removal`() throws {
        let domain = "settings-" + UUID().uuidString
        let legacy = domain + ".legacy"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            defaults.removePersistentDomain(forName: legacy)
        }
        defaults.setPersistentDomain(["agentKind": "codex", "agentideMigrationComplete": true], forName: domain)
        let old: [String: Any] = ["agentKind": "claude", "agentModel": "restored", "pushRequest": 6]
        defaults.setPersistentDomain(old, forName: legacy)
        try PortableSettings.backfill(defaults: defaults, domain: domain, legacyDomains: [legacy])
        #expect(defaults.string(forKey: "agentKind") == "codex")
        #expect(defaults.string(forKey: "agentModel") == "restored")
        #expect(defaults.object(forKey: "pushRequest") == nil)
        defaults.removeObject(forKey: "agentModel")
        try PortableSettings.backfill(defaults: defaults, domain: domain, legacyDomains: [legacy])
        #expect(defaults.object(forKey: "agentModel") == nil)
    }

    @Test
    func `an unreadable historical plist is retried and its feedback prompt recovered`() throws {
        let root = try TestSupport.temporaryDirectory("legacy-preferences")
        let domain = "prefs-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let file = root + "/legacy.plist"
        let retry = {
            try PortableSettings.backfill(
                defaults: defaults,
                domain: domain,
                legacyDomains: ["legacy"],
                preferencesDirectory: URL(filePath: root),
            )
        }
        try Data("<broken".utf8).write(to: URL(filePath: file))
        #expect(throws: (any Error).self) { try retry() }
        try Self.write([FeedbackPrompt.localReview.key: "Restored brief"], to: file)
        try retry()
        #expect(FeedbackPrompt.localReview.text(defaults: defaults) == "Restored brief")
    }

    @Test
    func `a linked settings file restores choices and writes back only changed preferences`() throws {
        let directory = try TestSupport.temporaryDirectory("portable-settings")
        let target = directory + "/dotfiles.plist"
        let file = directory + "/settings.plist"
        let domain = "settings-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try Self.write([
            "agentKind": "codex", "pushRequest": 5, "externalEditorCommand": "unexpected",
            "requireSignedCommits": false,
        ], to: target)
        try FileManager.default.createSymbolicLink(atPath: file, withDestinationPath: "dotfiles.plist")
        let settings = try PortableSettings(file: file, defaults: defaults, domain: domain)
        #expect(defaults.string(forKey: "agentKind") == "codex")
        #expect(defaults.object(forKey: "pushRequest") == nil)
        #expect(defaults.object(forKey: "externalEditorCommand") == nil)
        #expect(defaults.object(forKey: AppSettings.requireSignedCommitsKey) == nil)
        #expect(settings.restoredHostSettings[AppSettings.requireSignedCommitsKey] == "false")
        settings.useHostSetting(AppSettings.requireSignedCommitsKey, value: "false")
        #expect(defaults.object(forKey: AppSettings.requireSignedCommitsKey) as? Bool == false)
        #expect(settings.restoredHostSettings[AppSettings.externalEditorKey] == "unexpected")
        settings.useHostSetting(AppSettings.externalEditorKey, value: "different")
        #expect(defaults.object(forKey: AppSettings.externalEditorKey) == nil)
        settings.useHostSetting(AppSettings.externalEditorKey, value: "unexpected")
        #expect(defaults.string(forKey: AppSettings.externalEditorKey) == "unexpected")
        try Self.write(["agentKind": "claude", "futurePreference": true], to: target)
        defaults.set("high", forKey: "agentEffort")
        try settings.saveChanges()
        let contents = try Data(contentsOf: URL(filePath: target))
        let object = try unsafe PropertyListSerialization.propertyList(from: contents, format: nil)
        let values = try #require(object as? [String: Any])
        #expect(values["agentKind"] as? String == "claude")
        #expect(values["agentEffort"] as? String == "high")
        #expect(values["futurePreference"] as? Bool == true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file) == "dotfiles.plist")
        try Data("broken".utf8).write(to: URL(filePath: target))
        defaults.set("low", forKey: "agentEffort")
        #expect(throws: (any Error).self) { try settings.saveChanges() }
        #expect(try String(contentsOfFile: target, encoding: .utf8) == "broken")
    }

    @Test
    func `restored schedules are paused and preserve the saved instructions`() throws {
        let root = try TestSupport.temporaryDirectory("portable-prompts")
        let domain = "portable-prompts-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = MetadataStore(file: root + "/state.json")
        let file = root + "/settings.plist"
        let settings = try PortableSettings(file: file, defaults: defaults, domain: domain)
        var job = SavedPrompt(name: "Weekly audit", prompt: "Inspect changes")
        job.repositoryPath = "/repo"
        job.schedule = PromptSchedule()
        let memo = SavedPrompt(name: "Review", prompt: "Review this branch")
        try store.updatePersisting { $0.savedPrompts = [job, memo] }
        try settings.restorePrompts(in: store)
        var edited = job
        edited.prompt = "Edited in backup"
        try settings.savePrompt(edited)
        let fresh = MetadataStore(file: root + "/fresh.json")
        try settings.restorePrompts(in: fresh)
        let imported = try #require(fresh.load().savedPrompts.first { $0.id == job.id })
        #expect(imported.prompt == edited.prompt)
        #expect(imported.schedule == job.schedule)
        #expect(imported.isEnabled == false)
        #expect(fresh.load().savedPrompts.contains(memo))
        try settings.deletePrompt(id: memo.id)
        try settings.restorePrompts(in: store)
        #expect(store.load().savedPrompts == [imported])
        try settings.restorePrompts(in: fresh)
        #expect(fresh.load().savedPrompts.first?.prompt == edited.prompt)
    }

    @Test
    func `upgrade removes private settings from dotfiles and backs them up across edits`() throws {
        let root = try TestSupport.temporaryDirectory("portable-upgrade")
        let domain = "portable-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let file = root + "/settings.plist"
        var work = WorkMode()
        work.holidayUntil = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try JSONEncoder().encode(work)
        defaults.set(data, forKey: "workMode")
        defaults.set(true, forKey: "portablePreferencesImported")
        defaults.set("/System/Library/Sounds/Glass.aiff", forKey: "completionSound")
        defaults.set("zed --wait", forKey: AppSettings.externalEditorKey)
        let store = MetadataStore(file: root + "/state.json")
        let literal = "sntryu_" + String(repeating: "x", count: 32)
        let prompt = SavedPrompt(name: "Investigate", prompt: literal + " and $SENTRY_TOKEN")
        try store.updatePersisting { $0.savedPrompts = [prompt] }
        try Self.write([
            "workMode": data, "savedPrompts": [:], "promptSharingVersion": 1,
            FeedbackPrompt.localFix.key: "Private brief",
        ], to: file)
        let settings = try PortableSettings(file: file, defaults: defaults, domain: domain)
        try settings.restorePrompts(in: store)
        let xml = try String(contentsOfFile: file, encoding: .utf8)
        #expect(xml.contains("Glass.aiff"))
        #expect(xml.contains("zed --wait"))
        let backup = root + "/private/settings.plist"
        let archived = try String(contentsOfFile: backup, encoding: .utf8)
        for text in [prompt.prompt, "workMode", "savedPrompts", "promptSharingVersion", FeedbackPrompt.localFix.key] {
            #expect(xml.contains(text) == false)
            #expect(archived.contains(text))
        }
        #expect(archived.contains("<date>"))
        #expect(archived.contains("Glass.aiff") == false)
        work.organisations = ["Private organisation"]
        try defaults.set(JSONEncoder().encode(work), forKey: "workMode")
        defaults.set("Updated private brief", forKey: FeedbackPrompt.localFix.key)
        defaults.set(false, forKey: "notifyFinished")
        try settings.saveChanges()
        try settings.savePrompt(SavedPrompt(name: "New memo", prompt: "Private memo"))
        let edited = try String(contentsOfFile: backup, encoding: .utf8)
        let shared = try String(contentsOfFile: file, encoding: .utf8)
        for text in ["Private organisation", "Updated private brief", "Private memo"] {
            #expect(edited.contains(text))
            #expect(shared.contains(text) == false)
        }
    }

    @Test
    func `the last import keeps the local text when an older template was edited`() throws {
        let root = try TestSupport.temporaryDirectory("old-template")
        let domain = "settings-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = MetadataStore(file: root + "/state.json")
        let local = SavedPrompt(name: "Review", prompt: "Current instructions")
        try store.updatePersisting { $0.savedPrompts = [local] }
        let file = root + "/settings.plist"
        try Self.write([
            "promptSharingVersion": 1,
            "savedPrompts": [local.id.uuidString: ["name": local.name, "prompt": "Old instructions"]],
        ], to: file)
        let settings = try PortableSettings(file: file, defaults: defaults, domain: domain)
        try settings.restorePrompts(in: store)
        #expect(store.load().savedPrompts == [local])
        #expect(try String(contentsOfFile: file, encoding: .utf8).contains(local.prompt) == false)
        #expect(try String(contentsOfFile: root + "/private/settings.plist", encoding: .utf8).contains(local.prompt))
    }
}
