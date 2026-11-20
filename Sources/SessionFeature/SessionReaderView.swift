import SanductorData
import SanductorDomain
import SanductorInterface
import SwiftUI

/// A live session's conversation as the rendered log the
/// conversations page shows, in place of its terminal: text that
/// reflows with the pane and copies as formatted text. Read-only:
/// nothing typed here reaches the agent, whose terminal waits
/// underneath for the strip's button to bring it back.
public struct SessionReaderView: View {
    // MARK: Lifecycle

    /// Creates the reader for a session's agent in its worktree.
    /// `isActive` says whether the pane is the one on screen in a
    /// visible window: only then is the transcript read and watched.
    @preconcurrency
    public init(session: AgentSession, worktreePath: String, service: SessionService, isActive: Bool) {
        watch = Watch(isActive: isActive, activity: session.activity)
        let agent = session.agent
        _model = State(initialValue: SessionReaderModel {
            await service.liveTranscript(agent: agent, in: worktreePath).map { URL(fileURLWithPath: $0.path) }
        })
    }

    // MARK: Public

    public var body: some View {
        Group {
            if model.hasLoaded {
                TranscriptLogView(entries: model.entries)
            } else {
                LaunchProgressView("Reading the conversation…", waitingOn: "the agent's transcript")
            }
        }
        .task(id: watch) {
            if watch.isActive {
                await model.follow()
            }
        }
    }

    // MARK: Private

    /// What restarts the following: the pane coming on screen, and
    /// the agent changing what it is doing, which is when it may
    /// have begun a new transcript.
    private struct Watch: Equatable {
        let isActive: Bool
        // Read only by the synthesised Equatable conformance, which
        // periphery's assign-only check does not see.
        // periphery:ignore
        let activity: AgentActivity?
    }

    @State private var model: SessionReaderModel

    private let watch: Watch
}
