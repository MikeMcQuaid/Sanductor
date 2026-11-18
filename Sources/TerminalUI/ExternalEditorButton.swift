import SanductorData
import SwiftUI

/// Opens a worktree or directory at its root in the external editor
/// Settings → Editor chose: a text item in a menu, an icon in a pane's
/// toolbar. Without a command it is disabled rather than handing the
/// directory to its default app, which is Finder.
public struct ExternalEditorButton: View {
    // MARK: Lifecycle

    public init(path: String, iconOnly: Bool = false) {
        self.path = path
        self.iconOnly = iconOnly
    }

    // MARK: Public

    public var body: some View {
        if iconOnly {
            PaneIconButton("arrow.up.forward.app", help: help, disabled: isUnset) {
                FileOpener.openInExternalEditor(path)
            }
        } else {
            Button("Open in external editor") { FileOpener.openInExternalEditor(path) }
                .disabled(isUnset)
                .hoverHelp(help)
        }
    }

    // MARK: Private

    @AppStorage(AppSettings.externalEditorKey)
    private var command = ""

    private let path: String
    private let iconOnly: Bool

    private var isUnset: Bool {
        command.split(separator: " ").isEmpty
    }

    private var help: String {
        guard let executable = command.split(separator: " ").first else {
            return "Choose an external editor command in Settings → Editor first"
        }

        return "Open " + URL(filePath: path).lastPathComponent + " in "
            + URL(filePath: String(executable)).lastPathComponent
    }
}
