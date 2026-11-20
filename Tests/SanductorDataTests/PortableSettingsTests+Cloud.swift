import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension PortableSettingsTests {
    @Test
    func `an incomplete cloud archive preserves local private settings`() throws {
        let root = try TestSupport.temporaryDirectory("incomplete-private-backup")
        let domain = "partial-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("Keep this brief", forKey: FeedbackPrompt.localFix.key)
        let settings = try PortableSettings(file: root + "/settings.plist", defaults: defaults, domain: domain)
        let store = MetadataStore(file: root + "/state.json")
        try settings.restorePrompts(in: store)
        let good = try settings.mergeCloudArchive(nil, account: "account", store: store)
        settings.cloudArchiveSaved(good, account: "account")
        let broken = try PropertyListEncoder().encode(["promptSharingVersion": 2])
        #expect(throws: SessionServiceError.self) {
            try settings.mergeCloudArchive(broken, account: "account", store: store)
        }
        let backup = try String(contentsOf: settings.backup.destination, encoding: .utf8)
        #expect(backup.contains("Keep this brief"))
    }

    @Test
    func `two Macs restore private settings and reconcile offline edits and deletions`() throws {
        let root = try TestSupport.temporaryDirectory("cloud-settings")
        let account = "test-account"
        let firstDomain = "first-" + UUID().uuidString
        let secondDomain = "second-" + UUID().uuidString
        let firstDefaults = try #require(UserDefaults(suiteName: firstDomain))
        let secondDefaults = try #require(UserDefaults(suiteName: secondDomain))
        defer {
            firstDefaults.removePersistentDomain(forName: firstDomain)
            secondDefaults.removePersistentDomain(forName: secondDomain)
        }
        var mode = WorkMode()
        mode.organisations = ["Private organisation"]
        try firstDefaults.set(JSONEncoder().encode(mode), forKey: "workMode")
        firstDefaults.set("A private brief", forKey: FeedbackPrompt.localFix.key)
        firstDefaults.set("local editor", forKey: AppSettings.externalEditorKey)
        let first = try PortableSettings(
            file: root + "/first/settings.plist", defaults: firstDefaults, domain: firstDomain,
        )
        let second = try PortableSettings(
            file: root + "/second/settings.plist", defaults: secondDefaults, domain: secondDomain,
        )
        let firstStore = MetadataStore(file: root + "/first/state.json")
        let secondStore = MetadataStore(file: root + "/second/state.json")
        var job = SavedPrompt(name: "Scheduled", prompt: "Read $TOKEN")
        job.schedule = PromptSchedule()
        job.repositoryPath = "/repo"
        let local = SavedPrompt(name: "Offline", prompt: "Keep this")
        try firstStore.updatePersisting { $0.savedPrompts = [job] }
        try secondStore.updatePersisting { $0.savedPrompts = [local] }
        try first.restorePrompts(in: firstStore)
        try second.restorePrompts(in: secondStore)
        let upload = try first.mergeCloudArchive(nil, account: account, store: firstStore)
        first.cloudArchiveSaved(upload, account: account)
        let restored = try second.mergeCloudArchive(upload, account: account, store: secondStore)
        second.cloudArchiveSaved(restored, account: account)
        #expect(secondStore.load().savedPrompts.contains { $0.id == job.id && $0.isEnabled == false })
        #expect(secondStore.load().savedPrompts.contains { $0.id == local.id })
        #expect(secondDefaults.data(forKey: "workMode") != nil)
        #expect(second.restoredHostSettings[FeedbackPrompt.localFix.key] == "A private brief")
        #expect(second.restoredHostSettings[AppSettings.externalEditorKey] == nil)
        let dotfile = try String(contentsOfFile: root + "/second/settings.plist", encoding: .utf8)
        #expect(dotfile.contains("Read $TOKEN") == false)

        try second.deletePrompt(id: job.id)
        let other = SavedPrompt(name: "Concurrent", prompt: "Another edit")
        try first.savePrompt(other)
        let concurrent = try first.mergeCloudArchive(restored, account: account, store: firstStore)
        _ = try second.mergeCloudArchive(concurrent, account: account, store: secondStore)
        #expect(Set(secondStore.load().savedPrompts.map(\.id)) == [other.id, local.id])
    }
}
