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
            return log
        }

        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else {
            return log
        }

        if size < offset {
            offset = 0
            omitsEarlierRecords = false
            log.removeAll()
        }
        let window = UInt64(Self.maximumBytes)
        let start = max(offset, size > window ? size - window : 0)

        // The preceding byte distinguishes a complete first record from a fragment.
        let skipping = start > offset
        let readFrom = skipping ? start - 1 : start
        guard start < size, (try? handle.seek(toOffset: readFrom)) != nil,
              let data = try? handle.read(upToCount: Int(size - readFrom))
        else {
            return log
        }

        var records = data[...]
        if skipping {
            omitsEarlierRecords = true
            log.removeAll()
            guard let first = records.firstIndex(of: Self.newline) else {
                return log
            }

            records = records[(first + 1)...]
        }
        if includingFinalLine == false {
            guard let last = records.lastIndex(of: Self.newline) else {
                return log
            }

            records = records[...last]
        }
        offset = readFrom + UInt64(records.endIndex)
        guard let text = String(bytes: records, encoding: .utf8) else {
            return log
        }

        TranscriptParser.append(text, to: &log)
        trimHistory()
        return log
    }

    // MARK: Private

    private static let maximumBytes = 8_388_608
    private static let maximumEntries = 4_000
    private static let newline: UInt8 = .init(ascii: "\n")

    private var offset: UInt64 = 0
    private var log: [TranscriptEntry] = []

    private func trimHistory() {
        var bytes = 0
        let keep = log.suffix(Self.maximumEntries)
            .reversed()
            .prefix { entry in
                bytes += entry.text.utf8.count
                return bytes <= Self.maximumBytes
            }
            .count
        if log.count > keep {
            omitsEarlierRecords = true
            log.removeFirst(log.count - keep)
        }
    }
}
