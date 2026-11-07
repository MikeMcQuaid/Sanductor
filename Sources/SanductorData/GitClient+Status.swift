import Darwin
import SanductorDomain

public extension GitClient {
    /// Local state for views: HEAD and uncommitted content can change
    /// without changing the branch's commit counts or dirty flag.
    @concurrent
    func localState(worktreePath: String) async -> (isDirty: Bool, revision: String?) {
        guard let output = try? await git(
            GitWorktreeStatus.arguments + ["--branch", "--untracked-files=all"], in: worktreePath,
        ).standardOutput else {
            return (false, nil)
        }

        let status = GitWorktreeStatus(porcelain: output)
        var revision = output
        for path in status.changedPaths {
            var attributes = stat()
            guard unsafe lstat(worktreePath + "/" + path, &attributes) == 0 else {
                continue
            }

            revision += "\n" + [
                String(attributes.st_ino), String(attributes.st_size), String(attributes.st_mode),
                String(attributes.st_mtimespec.tv_sec), String(attributes.st_mtimespec.tv_nsec),
                String(attributes.st_ctimespec.tv_sec), String(attributes.st_ctimespec.tv_nsec),
            ].joined(separator: ":")
            if attributes.st_mode & S_IFMT == S_IFDIR {
                await revision += "\n" + (commitHash(of: "HEAD", worktreePath: worktreePath + "/" + path) ?? "")
            }
        }
        return (status.isDirty, LocalReviewInput.fingerprint(revision))
    }
}
