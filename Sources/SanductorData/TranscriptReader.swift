import Foundation
import SanductorDomain
import Synchronization

/// Reads agent transcript JSONL files across the user boundary; the
/// sandbox's export ACLs make them host-readable. Titles parse once
/// per file change, the treatment `CodexTranscriptIndex` gives the
/// other agent's tree: without the cache every poll re-read the
/// head of every transcript of every worktree.
public struct TranscriptReader: Sendable {
    // MARK: Lifecycle

    /// Creates a reader.
    public init() {
        // No configuration is needed.
    }

    // MARK: Public

    /// The newest transcript file in a directory, by modification
    /// time; each file is stat-ed once, not once per comparison.
    public func latestTranscript(in directory: String) -> URL? {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".jsonl") }
            .lazy
            .map { name in
                let path = directory + "/" + name
                return (path: path, modifiedAt: modificationDate(path))
            }
            .max { $0.modifiedAt < $1.modifiedAt }
            .map { URL(fileURLWithPath: $0.path) }
    }

    /// The resume id a transcript represents, its file name stem.
    public func resumeID(of transcript: URL) -> String {
        transcript.deletingPathExtension().lastPathComponent
    }

    /// When a transcript was last written, used for stall detection.
    public func modificationDate(_ path: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    /// Every session in a transcript directory, newest first, titled
    /// by the first user prompt. Titles are read from a head cache
    /// keyed by modification time, so a listing is a stat per file
    /// where it was a 64 KB read and decode per transcript; unlike
    /// the shared Codex tree, each worktree's directory is its own,
    /// so the listing itself is not worth caching against the poll.
    public func sessions(in directory: String, agent: AgentKind) -> [TranscriptSession] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasSuffix(".jsonl") }
            .map { name in
                let path = directory + "/" + name
                let modifiedAt = Int(modificationDate(path).timeIntervalSince1970)
                return TranscriptSession(
                    id: String(name.dropLast(".jsonl".count)),
                    path: path,
                    agent: agent,
                    modifiedAt: modifiedAt,
                    title: cachedTitle(ofTranscriptAt: path, modifiedAt: modifiedAt),
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The whole conversation as displayable log entries, tolerating
    /// unknown line shapes.
    public func entries(in transcript: URL) -> [TranscriptEntry] {
        guard let content = try? String(contentsOf: transcript, encoding: .utf8) else {
            return []
        }

        var results = [TranscriptEntry]()
        TranscriptParser.append(content, to: &results)
        return results
    }

    // MARK: Private

    /// One parsed title, keyed by file path and valid while the
    /// file's modification time stands.
    private struct CachedTitle {
        let modifiedAt: Int
        let title: String
    }

    /// Only the head of a transcript is read for its title; the first
    /// user prompt always sits there.
    private static let titleByteLimit = 65_536

    /// The title cache mirroring `CodexTranscriptIndex`'s: keyed by
    /// path, capped at the newest.
    private static let titles: Mutex<[String: CachedTitle]> = .init([:])
    private static let titleCap = 2_000

    /// The cached title while the file is unchanged, parsed afresh
    /// otherwise; the cache keeps the newest files when it fills.
    private func cachedTitle(ofTranscriptAt path: String, modifiedAt: Int) -> String {
        if let cached = Self.titles.withLock({ $0[path] }), cached.modifiedAt == modifiedAt {
            return cached.title
        }

        let title = title(ofTranscriptAt: path)
        Self.titles.withLock { titles in
            titles[path] = CachedTitle(modifiedAt: modifiedAt, title: title)
            if titles.count > Self.titleCap {
                let newest = titles
                    .sorted { $0.value.modifiedAt > $1.value.modifiedAt }
                    .prefix(Self.titleCap)
                titles = Dictionary(uniqueKeysWithValues: Array(newest))
            }
        }
        return title
    }

    private func title(ofTranscriptAt path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: Self.titleByteLimit),
              let head = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        defer { try? handle.close() }

        return TranscriptParser.title(in: head)
    }
}
