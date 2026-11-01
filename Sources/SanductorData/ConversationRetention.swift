import Foundation

/// A shared expiry policy for private backups and agent-owned transcripts.
enum ConversationRetention {
    // MARK: Internal

    struct File {
        // MARK: Lifecycle

        init?(path: String, worktree: String?) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let modifiedAt = attributes[.modificationDate] as? Date,
                  let byteCount = attributes[.size] as? Int
            else {
                return nil
            }

            self.path = path
            self.worktree = worktree ?? ""
            modified = modifiedAt
            size = byteCount
        }

        // MARK: Internal

        let path: String
        let worktree: String
        let modified: Date
        let size: Int

        var unchanged: Bool {
            let current = Self(path: path, worktree: worktree)
            return current?.modified == modified && current?.size == size
        }

        func expired(now: Date, livePaths: Set<String>, openFiles: Set<String>) -> Bool {
            guard now.timeIntervalSince(modified) > lifetime, openFiles.contains(path) == false else {
                return false
            }
            guard worktree.isEmpty == false else {
                return true
            }

            // A linked worktree has a .git file; a main checkout has a directory.
            if (try? FileManager.default.attributesOfItem(atPath: worktree + "/.git")[.type])
                as? FileAttributeType == .typeRegular
            {
                return false
            }
            return livePaths.contains(worktree) == false
        }
    }

    static let lifetime: TimeInterval = days * secondsPerDay

    /// Enumeration never follows linked directories or returns linked files.
    static func files(under root: String) -> [String] {
        let manager = FileManager.default
        guard (try? manager.attributesOfItem(atPath: root)[.type]) as? FileAttributeType == .typeDirectory,
              let entries = manager.enumerator(atPath: root)
        else {
            return []
        }

        return entries.compactMap { item in
            guard let entry = item as? String else {
                return nil
            }

            let path = root + "/" + entry
            guard (try? manager.attributesOfItem(atPath: path)[.type]) as? FileAttributeType == .typeRegular else {
                return nil
            }

            return path
        }
    }

    static func head(_ path: String) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return []
        }

        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes),
              let text = CodexTranscriptIndex.decodeHead(data)
        else {
            return []
        }

        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    // MARK: Private

    private static let days: TimeInterval = 30
    private static let secondsPerDay: TimeInterval = 86_400
    private static let headBytes = 262_144
}
