import Foundation
import SanductorDomain

extension GitClient {
    func repairRemoteRename(_ remote: String, in path: String, pushing: Bool, result: ProcessResult) async {
        guard let reported = Self.renamedRepository(in: result.standardError + "\n" + result.standardOutput),
              let current = await remoteURL(named: remote, worktreePath: path, forPush: pushing),
              let previous = Self.githubRepository(in: current), previous != reported,
              // A recursive fetch or push may have reported a submodule's redirect.
              let confirmation = try? await git(["ls-remote", current, "HEAD"], in: path),
              let renamed = Self.renamedRepository(in: confirmation.standardError), previous != renamed
        else {
            return
        }

        // Preserve separate fetch/push destinations and the original transport.
        for field in ["url", "pushurl", "sanductor-created-url"] {
            let key = "remote." + remote + "." + field
            guard let values = try? await git(["config", "--local", "--get-all", key], in: path) else {
                continue
            }

            for value in values.standardOutput.split(separator: "\n").map(String.init) {
                guard Self.githubRepository(in: value) == previous,
                      let range = value.range(of: previous, options: .backwards)
                else {
                    continue
                }

                let updated = value.replacingCharacters(in: range, with: renamed)
                _ = try? await git(
                    ["config", "--local", "--fixed-value", "--replace-all", key, updated, value], in: path,
                )
            }
        }
    }

    private static func renamedRepository(in output: String) -> String? {
        let lines = output.components(separatedBy: "\n").map { line in
            (line.hasPrefix("remote:") ? String(line.dropFirst("remote:".count)) : line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (index, line) in lines.enumerated() {
            let redirect = "warning: redirecting to "
            if line.hasPrefix(redirect) {
                return githubRepository(in: String(line.dropFirst(redirect.count)))
            }
            if line == "This repository moved. Please use the new location:", index + 1 < lines.count {
                return githubRepository(in: lines[index + 1])
            }
        }
        return nil
    }

    private static func githubRepository(in url: String) -> String? {
        guard url.range(
            of: #"^(https://github\.com/|git@github\.com:)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$"#,
            options: .regularExpression,
        ) != nil else {
            return nil
        }

        return GitHubRemote.fullName(ofURL: url)
    }
}
