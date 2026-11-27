import Darwin
import SanductorDomain

public extension GitClient {
    /// A status reading, including a configuration refusal that prevents reading the index.
    struct LocalState: Sendable {
        public var hasRebaseConflict = false
        public let isDirty: Bool
        public let revision: String?
        public let configurationError: String?
    }

    /// Local state for views: HEAD and uncommitted content can change
    /// without changing the branch's commit counts or dirty flag.
    @concurrent
    func localState(worktreePath: String) async -> LocalState {
        let output: String
        do {
            output = try await git(
                GitWorktreeStatus.arguments + ["--branch", "--untracked-files=all"], in: worktreePath,
            ).standardOutput
        } catch let error as ConfigurationError {
            return LocalState(isDirty: true, revision: nil, configurationError: error.localizedDescription)
        } catch {
            return LocalState(isDirty: false, revision: nil, configurationError: nil)
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
        var local = LocalState(
            isDirty: status.isDirty, revision: LocalReviewInput.fingerprint(revision), configurationError: nil,
        )
        if let branch = status.branch {
            let key = worktreePath + "#" + branch
            if let conflict = await RepositoryFacts.shared.rebaseConflicts[key],
               let tips = try? await git(["rev-parse", "refs/heads/" + branch, conflict.ref], in: worktreePath)
            {
                local.hasRebaseConflict = tips.standardOutput == conflict.tips
                if local.hasRebaseConflict == false {
                    await RepositoryFacts.shared.forget(conflict: conflict, for: key)
                }
            }
        }
        return local
    }
}
