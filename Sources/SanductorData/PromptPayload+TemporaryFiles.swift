import Foundation

extension PromptPayload {
    // MARK: Internal

    static func cleanTemporaryFiles(
        paths: WorkspacePaths,
        store: MetadataStore,
        protectedPaths: Set<String>,
        now: Date,
        reader: any TemporaryFileReading = LocalTemporaryFileReader(),
    ) {
        let directory = paths.sharedWorkspace + "/tmp"
        let diagnostics = directory + "/sanductor"
        let protected = protectedPaths.union(store.load().temporaryPromptFiles.keys)
            .union([diagnostics + "/performance-log"])
        for root in [directory, diagnostics, paths.promptsDirectory] {
            let descriptor = unsafe open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
            guard descriptor >= 0 else {
                continue
            }

            defer { close(descriptor) }
            guard let names = try? reader.names(in: descriptor) else {
                continue
            }

            for name in names {
                let path = root + "/" + name
                guard path != diagnostics, isProtected(path, by: protected) == false else {
                    continue
                }

                _ = removeExpiredTemporaryItem(
                    name,
                    relativeTo: descriptor,
                    before: now.addingTimeInterval(-temporaryFileLifetime),
                    reader: reader,
                )
            }
        }
    }

    static func isProtected(_ path: String, by protectedPaths: Set<String>) -> Bool {
        protectedPaths.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
    }

    static func removeExpiredTemporaryItem(
        _ path: String,
        before cutoff: Date,
        reader: any TemporaryFileReading,
        ignoringFileAge: Bool = false,
    ) -> Bool {
        let url = URL(fileURLWithPath: path)
        let directory = unsafe open(
            url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC,
        )
        guard directory >= 0 else {
            return false
        }

        defer { close(directory) }
        return removeExpiredTemporaryItem(
            url.lastPathComponent,
            relativeTo: directory,
            before: cutoff,
            reader: reader,
            ignoringFileAge: ignoringFileAge,
        )
    }

    // MARK: Private

    private static let temporaryFileLifetime: TimeInterval = 604_800

    private static func removeExpiredTemporaryItem(
        _ name: String,
        relativeTo parent: Int32,
        before cutoff: Date,
        reader: any TemporaryFileReading,
        ignoringFileAge: Bool = false,
    ) -> Bool {
        guard Task.isCancelled == false else {
            return false
        }

        do {
            guard let attributes = try reader.attributes(name, relativeTo: parent) else {
                return true
            }

            let expired = Date(timeIntervalSince1970: Double(attributes.st_mtimespec.tv_sec)
                + Double(attributes.st_mtimespec.tv_nsec) / Double(NSEC_PER_SEC)) < cutoff
            guard attributes.st_mode & S_IFMT == S_IFDIR else {
                guard ignoringFileAge || expired else {
                    return false
                }

                return unsafe unlinkat(parent, name, 0) == 0
            }

            let directory = unsafe openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else {
                return false
            }

            defer { close(directory) }
            var opened = stat()
            guard unsafe fstat(directory, &opened) == 0,
                  opened.st_dev == attributes.st_dev, opened.st_ino == attributes.st_ino
            else {
                return false
            }

            for child in try reader.names(in: directory) {
                _ = removeExpiredTemporaryItem(child, relativeTo: directory, before: cutoff, reader: reader)
            }
            guard expired, let current = try reader.attributes(name, relativeTo: parent),
                  current.st_dev == opened.st_dev, current.st_ino == opened.st_ino
            else {
                return false
            }

            // Refuse newly added children and a directory replaced by a symlink.
            return unsafe unlinkat(parent, name, AT_REMOVEDIR) == 0
        } catch {
            return false
        }
    }
}
