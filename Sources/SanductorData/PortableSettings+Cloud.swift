import Foundation

public extension PortableSettings {
    /// Merge a fetched archive with edits made offline, including prompt deletions.
    func mergeCloudArchive(_ data: Data?, account: String, store: MetadataStore) throws -> Data {
        try saveChanges()
        let key = "privateSettingsCloud." + account
        let remote = try Self.archive(data)
        let base = try Self.archive(defaults.data(forKey: key))
        var merged = [String: NSObject]()
        try backup.update { stored in
            let local = (stored ?? [:]).filter { Self.isPrivate($0.key) }
            merged = data == nil ? local : Self.merge(local, remote: remote, base: base, initial: base.isEmpty)
            if data != nil {
                let prompts = Self.merge(
                    local["savedPrompts"] as? [String: NSObject] ?? [:],
                    remote: remote["savedPrompts"] as? [String: NSObject] ?? [:],
                    base: base["savedPrompts"] as? [String: NSObject] ?? [:],
                    initial: base.isEmpty,
                )
                merged["savedPrompts"] = prompts as NSObject
            }
            // Validate every definition before changing the file or its live preferences.
            merged["savedPrompts"] = try Self.mergedPrompts(legacy: [:], backup: merged)
            _ = try Self.validated(merged)
            return merged
        }
        try restorePrompts(in: store)
        let local = try snapshot()
        let privateKeys = Set(local.keys).union(merged.keys).union(restoredHostSettings.keys).filter(Self.isPrivate)
        try apply(merged, to: local, keys: privateKeys)
        previous = try snapshot()
        // On a conflict, the next fetch compares local edits against the copy just merged.
        defaults.set(data, forKey: key)
        if let data, merged == remote {
            return data
        }

        return try PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0)
    }

    /// Advance the local comparison point only once CloudKit acknowledges the write.
    func cloudArchiveSaved(_ data: Data, account: String) {
        defaults.set(data, forKey: "privateSettingsCloud." + account)
    }

    private static func archive(_ data: Data?) throws -> [String: NSObject] {
        guard let data else {
            return [:]
        }
        guard let file = try unsafe PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: NSObject],
            file["promptSharingVersion"] is Int, file["savedPrompts"] is [String: NSObject],
            file.keys.allSatisfy(isPrivate)
        else {
            throw SessionServiceError("Invalid private settings archive in iCloud")
        }

        var values = file
        values["savedPrompts"] = try mergedPrompts(legacy: [:], backup: values)
        return values
    }

    private static func merge(
        _ local: [String: NSObject], remote: [String: NSObject], base: [String: NSObject], initial: Bool,
    ) -> [String: NSObject] {
        if initial {
            return local.merging(remote) { _, cloud in cloud }
        }

        var merged = remote
        for key in Set(base.keys).union(local.keys) where base[key] != local[key] {
            merged[key] = local[key]
        }
        return merged
    }
}
