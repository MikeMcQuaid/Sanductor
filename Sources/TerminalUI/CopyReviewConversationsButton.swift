import SanductorData
import SanductorDomain
import SwiftUI

/// The same manual copy action beside local and GitHub conversations.
public struct CopyReviewConversationsButton: View {
    // MARK: Lifecycle

    public init(
        threads: [ReviewThread],
        onResolve: @escaping ([ReviewThread]) async -> Void,
        pendingResolution: @escaping (ReviewThread) -> Bool,
    ) {
        self.threads = threads
        self.onResolve = onResolve
        self.pendingResolution = pendingResolution
    }

    // MARK: Public

    public var body: some View {
        BusyButton(
            "",
            busy: "",
            systemImage: "doc.on.doc",
            accessibilityLabel: "Copy " + String(open.count) + " conversations and findings",
            disabled: open.isEmpty,
        ) { modifiers in
            await copy(resolve: modifiers.contains(.option))
        }
        .controlSize(.small)
        .hoverHelp("Copy unresolved local AI and GitHub conversations and outside-diff findings, with files and lines; "
            + "exclude those marked Resolve on push. Option-click copies first, then marks GitHub conversations "
            + "Resolve on push and resolves local and outside-diff findings")
    }

    // MARK: Internal

    func copy(resolve: Bool, toClipboard: (String) -> Bool = { PromptClipboard.copy($0) }) async {
        let copied = open
        guard toClipboard(ReviewCopy.digest(of: copied)) else {
            return
        }

        if resolve {
            await onResolve(copied)
        }
    }

    // MARK: Private

    private let threads: [ReviewThread]
    private let onResolve: ([ReviewThread]) async -> Void
    private let pendingResolution: (ReviewThread) -> Bool

    private var open: [ReviewThread] {
        ReviewCopy.copyable(threads, pendingResolution: pendingResolution)
    }
}
