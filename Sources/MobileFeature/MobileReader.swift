#if os(iOS)
    import SanductorDomain
    import SanductorInterface
    import SanductorRemote
    import SwiftUI
    import Textual

    struct MobileReader: View {
        // MARK: Internal

        let model: MobileModel
        let session: MobileSession

        var body: some View {
            VStack(spacing: 0) {
                if let error {
                    ContentUnavailableView {
                        Label("Cannot read conversation", systemImage: "book.closed")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { attempt += 1 }
                    }
                } else if let entries, entries.isEmpty {
                    ContentUnavailableView("No recent messages", systemImage: "text.bubble")
                } else if let entries {
                    TranscriptLogView(entries: entries) { text in
                        StructuredText(markdown: text)
                            .textual
                            .structuredTextStyle(.gitHub)
                            .textual
                            .textSelection(.enabled)
                    }
                } else {
                    LaunchProgressView("Reading the conversation…", waitingOn: path == nil
                        ? "the updated Mac app to publish this agent's transcript" : "the agent's first message")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: phase == .active ? path : nil) {
                error = nil
                entries = nil
                guard phase == .active, let path, let client = model.remote else {
                    return
                }

                do {
                    try await client.followTranscript(at: path) { @MainActor latest in
                        if Task.isCancelled == false {
                            entries = latest
                        }
                    }
                } catch {
                    if Task.isCancelled == false {
                        self.error = error.localizedDescription
                    }
                }
            }
            .id(attempt)
            .safeAreaInset(edge: .bottom) {
                ReaderReplyField { reply in
                    guard let client = model.remote, model.isConnected else {
                        throw RemoteError("Reconnect before sending a reply.")
                    }

                    try await client.reply(reply, paneID: session.id)
                }
            }
        }

        // MARK: Private

        @Environment(\.scenePhase)
        private var phase
        @State private var attempt = 0
        // Nil while loading; an empty window is a completed read.
        // swiftlint:disable:next discouraged_optional_collection
        @State private var entries: [TranscriptEntry]?
        @State private var error: String?

        private var path: String? {
            model.sidebarEntry(for: session)?.transcriptPath
        }
    }
#endif
