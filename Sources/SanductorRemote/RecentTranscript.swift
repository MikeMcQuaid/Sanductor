import Foundation
import SanductorDomain

/// A bounded snapshot followed by live JSONL records from the same byte offset.
struct RecentTranscript {
    // MARK: Lifecycle

    init(fileSize: Int) {
        // Include the preceding byte: if the window starts on a record boundary
        // it is a newline, otherwise discard the fragment through its newline.
        offset = max(0, fileSize - Self.maximumBytes - 1)
        initialBytesRemaining = fileSize - offset
        lines = RemoteLines(skippingRecordsOver: Self.maximumBytes, skippingFirst: fileSize > Self.maximumBytes)
    }

    // MARK: Internal

    let offset: Int
    private(set) var entries: [TranscriptEntry] = []

    /// Publish the opening window once, then only when a visible record arrives.
    mutating func append(_ packet: Data) throws -> Bool {
        let loading = initialBytesRemaining > 0
        initialBytesRemaining = max(0, initialBytesRemaining - packet.count)
        let count = entries.count
        for line in try lines.append(packet) {
            let start = entries.count
            TranscriptParser.append(line, to: &entries)
            if start < entries.count, entries[start].role == .user {
                // One Claude prompt can contain several text blocks.
                userInputs.append(entries[start].id)
                if userInputs.count > Self.maximumTurns {
                    userInputs.removeFirst()
                }
            }
        }
        guard entries.count > count else {
            return loading && initialBytesRemaining == 0
        }

        let firstID = userInputs.count == Self.maximumTurns ? userInputs[0] : 0
        var bytes = 0
        let keep = entries.suffix(Self.maximumEntries)
            .reversed()
            .prefix { entry in
                bytes += entry.text.utf8.count
                return entry.id >= firstID && bytes <= Self.maximumBytes
            }
            .count
        entries.removeFirst(entries.count - keep)
        return initialBytesRemaining == 0
    }

    // MARK: Private

    private static let maximumTurns = 3
    private static let maximumEntries = 100
    private static let maximumBytes = 262_144

    private var initialBytesRemaining: Int
    private var lines: RemoteLines
    private var userInputs: [Int] = []
}
