import Foundation
import Observation
import SanductorDomain

/// The host's portable preferences. UserDefaults remains the in-process settings bus.
@preconcurrency
@Observable
@MainActor
public final class PortableSettings {
    // MARK: Lifecycle

    /// Opens the host file or its directly linked dotfiles target before models load.
    public init(
        file: String = NSHomeDirectory() + "/.sanductor/settings.plist",
        defaults: UserDefaults = .standard,
        domain: String = "com.mikemcquaid.Sanductor",
    ) throws {
        self.defaults = defaults
        self.domain = domain
        let url = URL(filePath: file)
        dotfile = try SettingsFile(url)
        backup = try SettingsFile(url.deletingLastPathComponent().appending(path: "private/settings.plist"))
        let local = try snapshot()
        let marker = "portableSettingsExpanded"
        try updateSettings(local: local) { shared, archived in
            if defaults.bool(forKey: marker) == false {
                let additional = defaults.bool(forKey: "portablePreferencesImported") ? Self.additionalKeys : Self.keys
                for key in additional where shared[key] == nil && Self.isPrivate(key) == false {
                    shared[key] = local[key]
                }
            }
            archived = try Self.portableValues(archived)
            let privatePreferences = archived.filter { Self.isPrivate($0.key) }
            try apply(shared.merging(privatePreferences) { _, copy in copy }, to: local, keys: Self.keys)
        }
        defaults.set(true, forKey: marker)
        defaults.set(true, forKey: "portablePreferencesImported")
        previous = try snapshot()
    }

    deinit {
        // The app owns the settings for its lifetime.
    }

    // MARK: Public

    /// Display names for settings that can initiate actions on the host.
    public static let hostSettingTitles: [String: String] = {
        var titles = [
            AppSettings.externalEditorKey: "External editor", AppSettings.externalBrowserKey: "External browser",
            AppSettings.requireSignedCommitsKey: "Require signed commits",
            AppSettings.repositoriesDirectoryKey: "Repositories",
            AppSettings.worktreesDirectoryKey: "Worktrees",
        ]
        for brief in FeedbackPrompt.allCases {
            titles[brief.key] = brief.rawValue
        }
        return titles
    }()

    /// Runs after a private settings edit has been written to disk.
    public var privateSettingsChanged: (() -> Void)?

    /// Restored host actions take effect after the user reviews the stored value.
    public private(set) var restoredHostSettings: [String: String] = [:]

    /// Recheck the old app and standalone executable domains independently of the rename migration.
    public static func backfill(
        defaults: UserDefaults = .standard,
        domain: String = "com.mikemcquaid.Sanductor",
        legacyDomains: [String] = ["Sanductor", "com.mikemcquaid.AgentIDE", "AgentIDE"],
        preferencesDirectory: URL = URL(filePath: NSHomeDirectory() + "/Library/Preferences"),
    ) throws {
        let marker = "configurationBackfilled"
        guard defaults.bool(forKey: marker) == false else {
            return
        }

        var current = defaults.persistentDomain(forName: domain) ?? [:]
        for name in [domain] + legacyDomains {
            let file = preferencesDirectory.appending(path: name + ".plist")
            let stored = try historicalPreferences(at: file)
            let source = (defaults.persistentDomain(forName: name) ?? [:]).merging(stored) { existing, _ in existing }
            for key in keys where current[key] == nil {
                if let value = source[key] {
                    defaults.set(value, forKey: key)
                    current[key] = value
                }
            }
        }
        defaults.set(true, forKey: marker)
    }

    /// Apply the value shown in Settings, even if the shared file has since changed.
    public func useHostSetting(_ key: String, value: String) {
        guard restoredHostSettings[key] == value else {
            return
        }

        if key == AppSettings.requireSignedCommitsKey {
            defaults.set(value == "true", forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
        restoredHostSettings[key] = nil
    }

    /// Merge this process's changes with the current file so another build or editor keeps its own edits.
    public func saveChanges() throws {
        let local = try snapshot()
        let changed = Self.keys.filter { previous[$0] != local[$0] }
        guard changed.isEmpty == false else {
            return
        }

        try updateSettings(local: local) { shared, archived in
            for key in changed {
                if Self.isPrivate(key) {
                    archived[key] = local[key]
                } else {
                    shared[key] = local[key]
                }
            }
        }
        for key in changed {
            restoredHostSettings[key] = nil
        }
        previous = local
        if changed.contains(where: Self.isPrivate) {
            privateSettingsChanged?()
        }
    }

    // MARK: Internal

    let backup: SettingsFile

    let defaults: UserDefaults
    var previous: [String: NSObject] = [:]

    var importedBackupPath: String? {
        get { defaults.string(forKey: "privateSettingsBackupPath") }
        set { defaults.set(newValue, forKey: "privateSettingsBackupPath") }
    }

    static func isPrivate(_ key: String) -> Bool {
        key == "workMode" || key == "savedPrompts" || key == "promptSharingVersion" || key.hasPrefix("feedbackPrompt.")
    }

    static func validated(_ input: [String: NSObject]) throws -> [String: NSObject] {
        let values = input.filter { keys.contains($0.key) }
        for (key, value) in values {
            if strings.contains(key), value is String {
                continue
            }
            if key == "workMode", (try? decode(WorkMode.self, from: value)) != nil {
                continue
            }
            // swiftlint:disable:next legacy_objc_type - A plist boolean and a numeric 1 have different CF types.
            if let number = value as? NSNumber {
                if toggles.contains(key), CFGetTypeID(number) == CFBooleanGetTypeID() {
                    continue
                }
                if fontSizes.contains(key), AppSettings.fontSizeRange.contains(number.doubleValue) {
                    continue
                }
                if key == AppSettings.pollIntervalKey, AppSettings.pollRange.contains(number.intValue),
                   number.doubleValue == Double(number.intValue)
                {
                    continue
                }
                if key == AppSettings.stackIntervalKey, AppSettings.stackRange.contains(number.doubleValue) {
                    continue
                }
            }
            throw SessionServiceError("Invalid value in settings.plist for " + key)
        }
        return values
    }

    func apply(_ values: [String: NSObject], to local: [String: NSObject], keys: Set<String>) throws {
        let imported = try Self.validated(values)
        for key in keys where local[key] != imported[key] || restoredHostSettings[key] != nil {
            if Self.hostKeys.contains(key) {
                let value = local[key] != imported[key] ? imported[key] : nil
                restoredHostSettings[key] = (value as? String) ?? (value as? Bool).map { String($0) }
            } else if key == "workMode", let value = imported[key] {
                let mode = try Self.decode(WorkMode.self, from: value)
                try defaults.set(JSONEncoder().encode(mode), forKey: key)
            } else {
                defaults.set(imported[key], forKey: key)
            }
        }
    }

    func snapshot() throws -> [String: NSObject] {
        try Self.portableValues((defaults.persistentDomain(forName: domain) ?? [:])
            .filter { Self.keys.contains($0.key) }
            .compactMapValues { $0 as? NSObject })
    }

    // MARK: Private

    private static let hostKeys: Set = .init(hostSettingTitles.keys)
    private static let additionalKeys = hostKeys.union([
        "completionSound", "needsInputSound", "sendFinishedToPhone", "sendNeedsInputToPhone",
    ])

    private static let strings: Set<String> = Set([
        "agentKind", "agentModel", "agentEffort", "sidebarMode", "sidebarRepositorySort", AppSettings.reviewAgentKey,
        AppSettings.interfaceFontNameKey, AppSettings.codeFontNameKey, AppSettings.repositoryFontNameKey,
        AppSettings.nameFontNameKey, AppSettings.tabFontNameKey,
    ] + AgentKind.allCases.flatMap { agent in
        [AppSettings.reviewModelKey(for: agent), AppSettings.reviewEffortKey(for: agent)]
    })
    .union(hostKeys.subtracting([AppSettings.requireSignedCommitsKey]))
    .union(["completionSound", "needsInputSound"])
    private static let toggles: Set<String> = [
        AppSettings.requireSignedCommitsKey, "sendFinishedToPhone", "sendNeedsInputToPhone",
        "notifyFinished", "notifyNeedsInput", "badgeNeedsInput", AppSettings.inhibitsSleepKey,
        AppSettings.newestCommentsFirstKey,
    ]
    private static let fontSizes: Set<String> = [
        AppSettings.interfaceFontSizeKey, AppSettings.codeFontSizeKey, AppSettings.repositoryFontSizeKey,
        AppSettings.nameFontSizeKey, AppSettings.tabFontSizeKey,
    ]
    private static let keys = strings.union(toggles)
        .union(fontSizes)
        .union(["workMode", AppSettings.pollIntervalKey, AppSettings.stackIntervalKey])

    private let domain: String
    private let dotfile: SettingsFile

    private static func historicalPreferences(at file: URL) throws -> [String: Any] {
        do {
            let data = try Data(contentsOf: file)
            guard let values = try unsafe PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
            else {
                throw SessionServiceError("Expected a preferences dictionary")
            }

            return values
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        } catch {
            throw SessionServiceError("Cannot read " + file.path + ": " + error.localizedDescription)
        }
    }

    /// Commit the private copy before removing anything from a previously shared file.
    private func updateSettings(
        local: [String: NSObject],
        _ change: (inout [String: NSObject], inout [String: NSObject]) throws -> Void,
    ) throws {
        try dotfile.update { existing in
            var shared = (existing ?? local).filter { Self.isPrivate($0.key) == false }
            let legacy = (existing ?? [:]).filter { Self.isPrivate($0.key) }
            try backup.update { stored in
                var archived = legacy.merging(stored ?? [:]) { _, saved in saved }
                if let stored, legacy["savedPrompts"] != nil, stored["savedPrompts"] != nil {
                    archived["savedPrompts"] = try Self.mergedPrompts(legacy: legacy, backup: stored)
                }
                if stored == nil || importedBackupPath != backup.destination.path {
                    archived = local.filter { Self.isPrivate($0.key) }.merging(archived) { _, saved in saved }
                }
                try change(&shared, &archived)
                return archived
            }
            return shared
        }
    }
}
