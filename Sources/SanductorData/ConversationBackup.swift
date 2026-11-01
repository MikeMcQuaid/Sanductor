import Foundation
import SanductorDomain

/// Keeps a copy of each worktree's newest conversation where the
/// sandbox cannot reach it.
///
/// Transcripts live in the sandbox user's home, which is disposable
/// by design and was emptied by accident once: the conversations went
/// with it while the code, which git and GitHub hold, was never at
/// risk. Only the conversation is copied for that reason. Copies stay
/// in the host's private app directory and are dropped with their
/// worktrees.
struct ConversationBackup {
    // MARK: Lifecycle

    /// Keeps automatic backups out of folders requiring privacy permission.
    init(paths: WorkspacePaths) {
        directory = paths.appDirectory + "/conversations"
    }

    // MARK: Internal

    /// Where copies are kept, so the app can say so.
    let directory: String

    /// Copies a worktree's newest conversation, replacing the copy
    /// already there: one file per worktree, the one a resume would
    /// continue. Cheap enough to call on every poll, since an
    /// unchanged transcript is not copied again.
    @concurrent
    func store(_ past: TranscriptSession, worktree: Worktree) async {
        let destination = path(worktree: worktree, extension: URL(fileURLWithPath: past.path).pathExtension) + ".gz"
        let manager = FileManager.default
        guard let source = try? manager.attributesOfItem(atPath: past.path) else {
            return
        }

        let copied = try? manager.attributesOfItem(atPath: destination)
        let sourceDate = source[.modificationDate] as? Date ?? .distantPast
        let copiedDate = copied?[.modificationDate] as? Date ?? .distantPast
        guard copied == nil || sourceDate > copiedDate else {
            return
        }

        try? manager.createDirectory(
            atPath: URL(fileURLWithPath: destination).deletingLastPathComponent().path,
            withIntermediateDirectories: true,
        )
        do {
            try await BackupCompression.write(source: past.path, destination: destination)
            try? manager.removeItem(atPath: URL(filePath: destination).deletingPathExtension().path)
            writeIndex(past, worktree: worktree)
        } catch {
            // Keep the last good copy and retry at the next backup.
        }
    }

    /// Drops a worktree's copy, which deleting the worktree does:
    /// the conversation is being thrown away deliberately, and a
    /// backup nobody asked to keep is clutter.
    func forget(worktree: Worktree) {
        let manager = FileManager.default
        let folder = directory + "/" + slug(worktree)
        try? manager.removeItem(atPath: folder)
    }

    // MARK: Private

    /// What the copy is called, whatever the agent named it.
    private static let transcriptName = "conversation"
    private static let indexName = "conversation.json"

    /// One folder per worktree, named for what it is rather than the
    /// uuid its path carries.
    private func slug(_ worktree: Worktree) -> String {
        (worktree.repositoryName + "-" + worktree.branch)
            .replacing("/", with: "-")
            .replacing(" ", with: "-")
    }

    private func path(worktree: Worktree, extension suffix: String) -> String {
        directory + "/" + slug(worktree) + "/" + Self.transcriptName + "." + (suffix.isEmpty ? "jsonl" : suffix)
    }

    /// Beside the copy, what it belongs to: a conversation file alone
    /// says nothing about which worktree, agent or session it came
    /// from, and a restore needs all three.
    private func writeIndex(_ past: TranscriptSession, worktree: Worktree) {
        let index: [String: String] = [
            "repository": worktree.repositoryName,
            "repositoryPath": worktree.repositoryPath,
            "branch": worktree.branch,
            "worktreePath": worktree.path,
            "agent": String(describing: past.agent),
            "resumeID": past.resumeID,
            "sourcePath": past.path,
            "storedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]) else {
            return
        }

        try? data.write(to: URL(fileURLWithPath: directory + "/" + slug(worktree) + "/" + Self.indexName))
    }
}
