import SanductorDomain
import SwiftUI

/// A read-only conversation log for a past session, themed like the
/// terminals: black on white in light mode, white on black in dark.
/// Assistant prose renders as Markdown and fenced code blocks are
/// syntax highlighted.
public struct TranscriptLogView<Assistant: View>: View {
    // MARK: Lifecycle

    /// Creates a log view over parsed transcript entries.
    public init(entries: [TranscriptEntry], @ViewBuilder assistant: @escaping (String) -> Assistant) {
        self.assistant = assistant
        self.entries = entries
    }

    // MARK: Public

    /// The scrolling log.
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(entries) { entry in
                    row(entry)
                }
                if entries.isEmpty {
                    Text("Empty transcript.").foregroundStyle(.secondary)
                }
            }
            .padding(spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Conversations read newest-last, so open at the end.
        .defaultScrollAnchor(.bottom)
        .interfaceFont(.callout)
        // The semantic text colours: they track appearance and the
        // Increase Contrast setting, where literal black and white
        // tracked nothing.
        #if os(macOS)
            .foregroundStyle(Color(nsColor: .textColor))
            .background(Color(nsColor: .textBackgroundColor))
        #endif
    }

    // MARK: Private

    private let assistant: (String) -> Assistant
    private let entries: [TranscriptEntry]

    private let spacing: CGFloat = 8

    @ViewBuilder
    private func row(_ entry: TranscriptEntry) -> some View {
        switch entry.role {
        case .user:
            Text("\(Text("❯ ").bold().foregroundStyle(.blue))\(Text(entry.text).bold())")
                .interfaceFont(.callout, monospaced: true)
                .textSelection(.enabled)

        case .assistant:
            // The shared renderer, so agent output, review comments
            // and pull request bodies all read the same.
            assistant(entry.text)

        case .tool:
            Text("⚙ " + entry.text)
                .interfaceFont(.caption, monospaced: true)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}
