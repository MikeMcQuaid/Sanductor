import Foundation

extension PromptPayload {
    /// During setup, enrol older prompts and staged attachments in the cleanup ledger.
    static func adoptExisting(paths: WorkspacePaths, store: MetadataStore) throws {
        let metadata = store.load()
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        ]
        let files = [paths.promptsDirectory, paths.sharedWorkspace + "/tmp"].flatMap { directory -> [URL] in
            guard (try? FileManager.default.attributesOfItem(atPath: directory)[.type]) as? FileAttributeType
                == .typeDirectory
            else {
                return []
            }

            return (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: directory), includingPropertiesForKeys: Array(keys),
            )) ?? []
        }
        var records = [String: TemporaryPromptFile]()
        for file in files where metadata.temporaryPromptFiles[file.path] == nil {
            guard owns(file, paths: paths, metadata: metadata),
                  let attributes = try? file.resourceValues(forKeys: keys), attributes.isSymbolicLink == false,
                  attributes.isRegularFile == true || (attributes.isDirectory == true
                      && file.deletingLastPathComponent().path == paths.sharedWorkspace + "/tmp"),
                  let date = attributes.contentModificationDate
            else {
                continue
            }

            let attempt = metadata.pullRequestAutomation.values.compactMap(\.attempt).first { attempt in
                file.lastPathComponent.hasPrefix("autofix-" + attempt.id + ".")
                    || file.lastPathComponent == "autofix-" + attempt.id + "-commit.md"
            }
            records[file.path] = TemporaryPromptFile(
                paneID: attempt?.paneID, sessionName: attempt?.sessionName, createdAt: date,
            )
        }
        guard records.isEmpty == false else {
            return
        }

        try store.updatePersisting { value in
            value.temporaryPromptFiles.merge(records) { current, _ in current }
        }
    }

    static func owns(_ file: URL, paths: WorkspacePaths, metadata: AppMetadata) -> Bool {
        let directory = file.deletingLastPathComponent().standardizedFileURL
        guard (try? FileManager.default.attributesOfItem(atPath: directory.path)[.type]) as? FileAttributeType
            == .typeDirectory
        else {
            return false
        }

        if directory == URL(fileURLWithPath: paths.sharedWorkspace + "/tmp").standardizedFileURL {
            return file.lastPathComponent.wholeMatch(
                of: /drop-[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}-[\s\S]+/,
            ) != nil
        }

        return directory
            == URL(fileURLWithPath: paths.promptsDirectory).standardizedFileURL
            && ["md", "json"].contains(file.pathExtension)
            && (file.lastPathComponent.hasPrefix("prompt-") || file.lastPathComponent.hasPrefix("autofix-")
                || metadata.prompts[file.deletingPathExtension().lastPathComponent] != nil)
    }
}
