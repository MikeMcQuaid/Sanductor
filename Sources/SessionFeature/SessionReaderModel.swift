import Foundation
import Observation
import SanductorData
import SanductorDomain

/// A live session's conversation, read as its agent writes it. Kept
/// out of the view so following tests without a window; the
/// transcript lookup is a stored closure, so tests replace it.
@preconcurrency
@Observable
@MainActor
final class SessionReaderModel {
    // MARK: Lifecycle

    /// Creates a reader over whichever transcript the lookup names
    /// each time following starts, asked again every `discovery`
    /// while it names none.
    init(
        discovery: Duration = .seconds(RefreshCadence.transcriptDiscoverySeconds),
        transcript: @escaping () async -> URL?,
    ) {
        self.discovery = discovery
        self.transcript = transcript
    }

    deinit {
        // Following is owned by the view's task.
    }

    // MARK: Internal

    private(set) var omitsEarlierRecords = false
    private(set) var entries: [TranscriptEntry] = []

    /// False until the first read lands, so the pane shows loading
    /// rather than an empty log that fills in later.
    private(set) var hasLoaded = false

    /// Reads the session's transcript and keeps reading as it grows,
    /// until cancelled. Starting again looks the transcript up
    /// afresh, since the agent may have begun a new one, and picks
    /// up an unchanged one where the last read stopped. Cancelling
    /// does not stop a lookup or a read already under way, so each
    /// answer is checked before it is shown: a follow that was
    /// replaced must not undo what its replacement shows.
    func follow() async {
        var current = await transcript()
        // No event announces a first transcript (see
        // `RefreshCadence.transcriptDiscoverySeconds`), so the
        // lookup is asked again until one appears.
        while current == nil, Task.isCancelled == false {
            show([])
            guard await (try? Task.sleep(for: discovery)) != nil else {
                return
            }

            current = await transcript()
        }
        guard let current, Task.isCancelled == false else {
            return
        }

        let following = tail.flatMap { $0.transcript == current ? $0 : nil } ?? TranscriptTail(transcript: current)
        tail = following
        for await _ in following.changes() {
            let latest = await following.entries()
            let omitted = await following.omitsEarlierRecords
            guard Task.isCancelled == false else {
                return
            }

            show(latest, omitted: omitted)
        }
    }

    // MARK: Private

    private let discovery: Duration
    private let transcript: () async -> URL?
    private var tail: TranscriptTail?

    /// Publishes only what changed: a write that adds no entry (a
    /// tool result, the agent's bookkeeping) must redraw nothing.
    private func show(_ latest: [TranscriptEntry], omitted: Bool = false) {
        if omitsEarlierRecords != omitted {
            omitsEarlierRecords = omitted
        }
        if latest != entries {
            entries = latest
        }
        if hasLoaded == false {
            hasLoaded = true
        }
    }
}
