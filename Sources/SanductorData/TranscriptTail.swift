import Foundation
import SanductorDomain

/// Follows one transcript while its agent writes it. Each read takes
/// only the whole lines appended since the last, so a long
/// conversation is decoded once however often it grows.
public actor TranscriptTail {
    // MARK: Lifecycle

    /// Creates a follower that has read nothing yet.
    public init(transcript: URL) {
        self.transcript = transcript
    }

    deinit {
        // Nothing is held open between reads.
    }

    // MARK: Public

    /// The file being followed.
    public nonisolated let transcript: URL

    /// Whether the display window has left earlier records out.
    public private(set) var omitsEarlierRecords = false

    /// A ring for what is already written, then one each time the
    /// agent writes more; rings coalesce while a read is under way.
    /// The watch ends with the stream. A file that cannot be watched
    /// rings once and finishes, which still shows what it holds.
    public nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield()
            let descriptor = unsafe open(transcript.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .global(qos: .utility),
            )
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }

    /// Reads a bounded tail, keeping an unfinished record for the next live read.
    public func entries(includingFinalLine: Bool = false) -> [TranscriptEntry] {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else {
            return displayEntries
        }

        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else {
            return displayEntries
        }

        if size < offset {
            offset = 0
            omitsEarlierRecords = false
            log.removeAll()
        }
        let unread = size - offset
        guard unread > 0 else {
            return displayEntries
        }

        for limit in [Self.openingBytes, Self.lookbackBytes] {
            let start = size - min(unread, limit)
            let skipping = start > offset
            let batch = read(handle, from: start, to: size, includingFinalLine: includingFinalLine)
            var latest = log
            if let batch {
                TranscriptParser.append(batch.text, to: &latest)
            }
            if skipping, latest.count == log.count, limit == Self.openingBytes {
                continue
            }
            if let batch {
                offset = batch.end
            }
            if latest.count > log.count {
                if skipping {
                    latest.removeFirst(log.count)
                }
                log = latest
                trimHistory()
            }
            omitsEarlierRecords = omitsEarlierRecords || skipping
            break
        }
        return displayEntries
    }

    // MARK: Private

    private static let openingBytes: UInt64 = 262_144
    private static let lookbackBytes: UInt64 = 8_388_608
    private static let maximumTextBytes = 16_384
    private static let maximumEntries = 24
    private static let newline: UInt8 = .init(ascii: "\n")

    private var offset: UInt64 = 0
    private var log: [TranscriptEntry] = []

    /// Keep the full final entry for deduplicating the next live record.
    private var displayEntries: [TranscriptEntry] {
        guard let last = log.last, last.text.utf8.count > Self.maximumTextBytes else {
            return log
        }

        let cut = last.text.utf8.index(last.text.endIndex, offsetBy: -Self.maximumTextBytes)
        let start = cut.samePosition(in: last.text) ?? last.text.index(after: cut)
        return [TranscriptEntry(id: last.id, role: last.role, text: String(last.text[start...]))]
    }

    private func read(
        _ handle: FileHandle, from start: UInt64, to size: UInt64, includingFinalLine: Bool,
    ) -> (text: String, end: UInt64)? {
        // The preceding byte distinguishes a complete first record from a fragment.
        let skipping = start > offset
        let readFrom = skipping ? start - 1 : start
        guard (try? handle.seek(toOffset: readFrom)) != nil,
              let data = try? handle.read(upToCount: Int(size - readFrom))
        else {
            return nil
        }

        var records = data[...]
        if skipping {
            guard let first = records.firstIndex(of: Self.newline) else {
                return nil
            }

            records = records[(first + 1)...]
        }
        if includingFinalLine == false {
            guard let last = records.lastIndex(of: Self.newline) else {
                return nil
            }

            records = records[...last]
        }
        guard let text = String(bytes: records, encoding: .utf8) else {
            return nil
        }

        return (text, readFrom + UInt64(records.endIndex))
    }

    private func trimHistory() {
        var bytes = 0
        let keep = log.suffix(Self.maximumEntries)
            .reversed()
            .prefix { entry in
                bytes += entry.text.utf8.count
                return bytes <= Self.maximumTextBytes
            }
            .count
        if log.count > keep {
            omitsEarlierRecords = true
            log.removeFirst(log.count - max(1, keep))
        }
    }
}
