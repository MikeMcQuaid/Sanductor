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

    /// The log so far, with whatever was appended since the last call.
    public func entries() -> [TranscriptEntry] {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else {
            return log
        }

        defer { try? handle.close() }

        try? handle.seek(toOffset: offset)
        // Whole lines only: the agent may be midway through its last.
        guard let data = try? handle.readToEnd(), let end = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return log
        }

        let whole = data[...end]
        offset += UInt64(whole.count)
        if let lines = String(bytes: whole, encoding: .utf8) {
            TranscriptParser.append(lines, to: &log)
        }
        return log
    }

    // MARK: Private

    private var offset: UInt64 = 0
    private var log: [TranscriptEntry] = []
}
