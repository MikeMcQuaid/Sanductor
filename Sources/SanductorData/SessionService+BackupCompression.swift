import Foundation

public extension SessionService {
    /// Outside the path that paints or refreshes the sidebar.
    @concurrent
    func compressConversationBackups() async {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: paths.appDirectory)) ?? []
        for name in names where name == "conversations" || name.hasPrefix(".agentide-backup-") {
            let root = paths.appDirectory + "/" + name
            guard (try? manager.attributesOfItem(atPath: root)[.type]) as? FileAttributeType == .typeDirectory,
                  let entries = manager.enumerator(atPath: root)
            else {
                continue
            }

            while let entry = entries.nextObject() as? String {
                guard Task.isCancelled == false else {
                    return
                }

                let path = root + "/" + entry
                let attributes = try? manager.attributesOfItem(atPath: path)
                if attributes?[.type] as? FileAttributeType == .typeRegular,
                   entry.contains(".gz.compression-"),
                   let suffix = entry.components(separatedBy: ".gz.compression-").last,
                   UUID(uuidString: suffix) != nil,
                   let created = attributes?[.creationDate] as? Date,
                   Date().timeIntervalSince(created) > Self.backupScratchLifetime
                {
                    try? manager.removeItem(atPath: path)
                    continue
                }
                guard attributes?[.type] as? FileAttributeType == .typeRegular,
                      entry.hasSuffix(".gz") == false,
                      entry.contains(".compression-") == false,
                      URL(filePath: path).lastPathComponent != "conversation.json",
                      URL(filePath: path).lastPathComponent != ".retention-start",
                      manager.fileExists(atPath: path + ".gz") == false
                else {
                    continue
                }

                do {
                    try await BackupCompression.write(source: path, destination: path + ".gz")
                    let current = try manager.attributesOfItem(atPath: path)
                    if current[.modificationDate] as? Date == attributes?[.modificationDate] as? Date,
                       current[.size] as? Int == attributes?[.size] as? Int
                    {
                        try manager.removeItem(atPath: path)
                    }
                } catch {
                    // Leave the source intact; the next launch retries it.
                }
            }
        }
    }

    private static let backupScratchLifetime: TimeInterval = 86_400
}
