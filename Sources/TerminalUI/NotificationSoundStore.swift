import CryptoKit
import Foundation

/// Custom sounds are imported explicitly; playback never reopens their source.
public struct NotificationSoundStore {
    // MARK: Lifecycle

    /// Uses private app storage unless a test supplies its own directory.
    public init(directory: URL = URL(filePath: NSHomeDirectory() + "/.sanductor/sounds")) {
        self.directory = directory
    }

    // MARK: Public

    /// Copies an explicitly selected sound without changing its remembered source.
    public func importFile(at path: String) throws {
        guard path.isEmpty == false, isSystemSound(path) == false else {
            return
        }

        let data = try Data(contentsOf: URL(filePath: path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: URL(filePath: playbackPath(for: path)), options: .atomic)
    }

    /// Checks only private storage, so a missing import never prompts for access.
    public func needsImport(_ path: String) -> Bool {
        path.isEmpty == false && isSystemSound(path) == false
            && FileManager.default.fileExists(atPath: playbackPath(for: path)) == false
    }

    /// Keeps sounds selected by either event and removes superseded imports.
    public func removeUnused(keeping sources: [String]) {
        let kept = Set(sources.filter { $0.isEmpty == false }.map { playbackPath(for: $0) })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where kept.contains(file.path) == false {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Internal

    func playbackPath(for path: String) -> String {
        guard path.isEmpty == false, isSystemSound(path) == false else {
            return path
        }

        let name = SHA256.hash(data: Data(path.utf8)).map { unsafe String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
            .appendingPathExtension(URL(filePath: path).pathExtension)
            .path
    }

    // MARK: Private

    private let directory: URL

    private func isSystemSound(_ path: String) -> Bool {
        URL(filePath: path).standardizedFileURL.deletingLastPathComponent().path == "/System/Library/Sounds"
    }
}
