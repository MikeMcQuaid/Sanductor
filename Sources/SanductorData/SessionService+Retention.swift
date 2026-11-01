import Foundation
import SanductorDomain

public extension SessionService {
    /// Maintenance stays off the launch and sidebar refresh paths.
    @concurrent
    func maintainConversations() async {
        repeat {
            await expireConversations()
            await compressConversationBackups()
            do {
                try await Task.sleep(for: .seconds(RefreshCadence.conversationMaintenanceSeconds))
            } catch {
                return
            }
        } while Task.isCancelled == false
    }
}

extension SessionService {
    private static let retentionIndexBytes = 65_536

    @concurrent
    func expireConversations(now: Date = Date()) async {
        guard let panes = try? await herdr.panes() else {
            return
        }

        let payload = "/usr/sbin/lsof -n -P -u " + launcher.sandboxUser.shellQuoted + " -Ffn"
        let command = NSUserName() == launcher.sandboxUser ? ["/bin/zsh", "-c", payload] : launcher.command(
            payload: payload,
            initialDirectory: paths.sandboxHome,
            sessionID: UUID().uuidString,
            sessionName: "sanductor-retention",
        )
        guard let opened = try? await processes.run(command, workingDirectory: "/", environment: [:]),
              opened.succeeded
        else {
            return
        }

        let lines = opened.standardOutput.split(separator: "\n").map(String.init)
        let openFiles = Set(lines.filter { $0.hasPrefix("n/") }.map { String($0.dropFirst()) })
        var livePaths = Set(panes.filter { $0.isFinished == false }.map(\.currentPath))
        for (previous, line) in zip(lines, lines.dropFirst()) where previous == "fcwd" && line.hasPrefix("n/") {
            livePaths.insert(String(line.dropFirst()))
        }
        var files = await backupRetentionFiles(now: now)
        for runner in runners {
            files += runner.conversationFiles(sandboxHome: paths.sandboxHome).compactMap { path, worktree in
                ConversationRetention.File(path: path, worktree: retentionWorktree(worktree))
            }
        }
        await removeExpiredFiles(files.filter { $0.expired(now: now, livePaths: livePaths, openFiles: openFiles) })
    }

    private func removeExpiredFiles(_ files: [ConversationRetention.File]) async {
        var commands = [String]()
        for file in files {
            guard Task.isCancelled == false else {
                return
            }
            guard file.unchanged else {
                continue
            }

            if file.path.hasPrefix(paths.appDirectory + "/") || NSUserName() == launcher.sandboxUser {
                try? FileManager.default.removeItem(atPath: file.path)
            } else {
                // Originals belong to the sandbox account; batch the owner-side retry.
                guard file.path.hasPrefix(paths.sandboxHome + "/"), file.unchanged else {
                    continue
                }

                let path = file.path.shellQuoted
                let stamp = "\(Int(file.modified.timeIntervalSince1970)):\(file.size)".shellQuoted
                commands.append(
                    "if [ ! -L " + path + " ] && [ -f " + path + " ] && [ \"$(/usr/bin/stat -f '%m:%z' "
                        + path + ")\" = " + stamp + " ]; then /bin/rm -f -- " + path + "; fi",
                )
                if commands.count == 100 {
                    await removeExpiredOriginals(commands)
                    commands.removeAll()
                }
            }
        }
        if commands.isEmpty == false {
            await removeExpiredOriginals(commands)
        }
    }

    private func retentionWorktree(_ path: String?) -> String? {
        guard let path, path.hasPrefix(paths.sharedWorkspace + "/") else {
            return nil
        }

        return path
    }

    private func removeExpiredOriginals(_ commands: [String]) async {
        let command = launcher.command(
            payload: commands.joined(separator: "\n"),
            initialDirectory: paths.sandboxHome,
            sessionID: UUID().uuidString,
            sessionName: "sanductor-retention",
        )
        _ = try? await processes.run(command, workingDirectory: "/", environment: [:])
    }

    @concurrent
    func backupRetentionFiles(now: Date) async -> [ConversationRetention.File] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: paths.appDirectory)) ?? []
        var files = [ConversationRetention.File]()
        for name in names where name == "conversations" || name.hasPrefix(".agentide-backup-") {
            let root = paths.appDirectory + "/" + name
            guard (try? manager.attributesOfItem(atPath: root)[.type]) as? FileAttributeType == .typeDirectory else {
                continue
            }

            if name != "conversations" {
                let marker = root + "/.retention-start"
                guard let started = (try? manager.attributesOfItem(atPath: marker)[.modificationDate]) as? Date else {
                    try? Data().write(to: URL(filePath: marker), options: .withoutOverwriting)
                    continue
                }
                guard now.timeIntervalSince(started) > ConversationRetention.lifetime else {
                    continue
                }
            }
            let paths = ConversationRetention.files(under: root)
            var worktrees = [String: String]()
            for path in paths where path.hasSuffix("/conversation.json") || path.hasSuffix("/conversation.json.gz") {
                let data: Data?
                if path.hasSuffix(".gz") {
                    let result = try? await FoundationProcessRunner().run(
                        ["/usr/bin/gzip", "-cd", "--", path],
                        workingDirectory: "/",
                        environment: [:],
                        outputLimit: Self.retentionIndexBytes,
                    )
                    data = result?.succeeded == true ? result.map { Data($0.standardOutput.utf8) } : nil
                } else {
                    data = try? Data(contentsOf: URL(filePath: path))
                }
                if let data, let index = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
                    worktrees[URL(filePath: path).deletingLastPathComponent().path] = index["worktreePath"]
                }
            }
            files += paths.filter { $0.hasSuffix("/.retention-start") == false }.compactMap { path in
                ConversationRetention.File(
                    path: path,
                    worktree: retentionWorktree(worktrees[URL(filePath: path).deletingLastPathComponent().path]),
                )
            }
        }
        return files
    }
}
