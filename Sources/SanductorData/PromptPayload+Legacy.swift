import Foundation

extension PromptPayload {
    /// Once during setup, enrol files created before the cleanup ledger existed.
    static func adoptExisting(paths: WorkspacePaths, store: MetadataStore) throws {
        let metadata = store.load()
        let directory = URL(fileURLWithPath: paths.promptsDirectory)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        )
        var records = [String: TemporaryPromptFile]()
        for file in files where metadata.temporaryPromptFiles[file.path] == nil {
            guard owns(file, paths: paths, metadata: metadata),
                  let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  attributes.isRegularFile == true, let date = attributes.contentModificationDate
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
        file.deletingLastPathComponent().standardizedFileURL
            == URL(fileURLWithPath: paths.promptsDirectory).standardizedFileURL
            && ["md", "json"].contains(file.pathExtension)
            && (file.lastPathComponent.hasPrefix("prompt-") || file.lastPathComponent.hasPrefix("autofix-")
                || metadata.prompts[file.deletingPathExtension().lastPathComponent] != nil)
    }
}
