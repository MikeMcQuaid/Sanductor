import SanductorData
import SanductorDomain
import SwiftUI

/// The same manual copy action beside local and GitHub conversations.
public struct CopyReviewConversationsButton: View {
    // MARK: Lifecycle

    public init(threads: [ReviewThread]) {
        self.threads = threads
    }

    // MARK: Public

    public var body: some View {
        PaneIconButton(
            "doc.on.doc",
            help: "Copy unresolved local AI and GitHub conversations and outside-diff findings, with files and lines",
            disabled: open.isEmpty,
        ) {
            PromptClipboard.copy(ReviewCopy.digest(of: open))
        }
        .accessibilityLabel("Copy " + String(open.count) + " conversations and findings")
    }

    // MARK: Private

    private let threads: [ReviewThread]

    private var open: [ReviewThread] {
        threads.filter { $0.isResolved == false }
    }
}
