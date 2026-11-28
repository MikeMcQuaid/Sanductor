import AppKit
import Foundation
import SanductorData
import SwiftUI

// MARK: - UtilityTabTarget

/// The utility tab names modules write to the `utilityTab` storage
/// key. They match `UtilityTab`'s raw values in the app; names
/// survive tab reordering, which silently repointed the integer
/// indices this bus used to carry.
public enum UtilityTabTarget {
    // MARK: Public

    /// The cross-module storage key that switches the utility tab.
    public static let key = "utilityTab"

    /// The key that shows the utility pane, for the panes that must
    /// be seen whether or not it was open.
    public static let visibilityKey = "showsUtilityPane"

    /// The embedded browser tab.
    public static let browser = "browser"

    /// The address the browser is being asked for, and the count of
    /// times one has been asked for. The count is what a pane
    /// watches: asking twice for the same page writes the same
    /// string, which publishes no change, so a link clicked after
    /// the browser had wandered off elsewhere did nothing at all.
    public static let addressKey = "browserAddress"

    /// The count of address requests, which is what changes when the
    /// same page is asked for twice.
    public static let requestKey = "browserRequest"

    /// The editor tab.
    public static let editor = "editor"

    /// The errors tab.
    public static let errors = "errors"

    /// Bumped whenever a pull request summary is cached by whichever
    /// surface fetched it, so the sidebar's rows and the pull
    /// request pane, which read the same caches, repaint at once
    /// rather than on their next poll.
    public static let pullRequestCacheKey = "pullRequestCacheGeneration"

    /// Local resolution marks redraw both review panes without fetching GitHub.
    public static let resolutionMarksKey = "resolutionMarksGeneration"

    /// Bumped by the menu bar's Refresh and by every action of the
    /// app's own that moves a branch (a push, a rebase, a commit, an
    /// amend), so the sidebar reads git now rather than on its next
    /// poll.
    public static let dashboardRefreshKey = "dashboardRefreshRequest"

    /// Asks the sidebar for a reading now.
    public static func requestSidebarRefresh() {
        bump(dashboardRefreshKey)
    }

    /// Tells every surface reading the pull request caches that one
    /// of them changed.
    public static func pullRequestCacheChanged() {
        bump(pullRequestCacheKey)
    }

    /// Repaints pending marks without invalidating remote data.
    public static func resolutionMarksChanged() {
        bump(resolutionMarksKey)
    }

    // MARK: Private

    private static func bump(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}

// MARK: - LinkOpener

/// Opens web links: in the embedded Browser tab by default, in the
/// browser Settings chose (the system default until set) when the
/// command key is held.
public enum LinkOpener {
    // MARK: Public

    /// The shared symbol for opening a page in the browser.
    public static let systemImage = "safari"

    /// The action every in-app link takes, installed at the window's
    /// root: web links route through `open`, so a link in a
    /// conversation or pull request lands in the embedded browser,
    /// and anything else is refused with a message. Handing those to
    /// the system opener produced an unhelpful "error -50" dialog
    /// for relative and schemeless links.
    public static let action = OpenURLAction { url in
        MainActor.assumeIsolated {
            guard isWeb(url) else {
                ErrorLog.shared.report("Not a web link, so not opened: " + url.absoluteString)
                return .discarded
            }

            open(url.absoluteString)
            return .handled
        }
    }

    /// Routes an address by the command key; only web links reach
    /// the external browser, for the same reason as `action`.
    @preconcurrency
    @MainActor
    public static func open(_ address: String, inExternalBrowser: Bool = NSEvent.modifierFlags.contains(.command)) {
        if inExternalBrowser {
            guard let url = URL(string: address), isWeb(url) else {
                return
            }

            let chosen = UserDefaults.standard.string(forKey: "externalBrowser") ?? ""
            if chosen.isEmpty {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: URL(filePath: chosen),
                    configuration: NSWorkspace.OpenConfiguration(),
                )
            }
        } else {
            let defaults = UserDefaults.standard
            pendingBrowserAddress = address
            defaults.set(address, forKey: UtilityTabTarget.addressKey)
            defaults.set(defaults.integer(forKey: UtilityTabTarget.requestKey) + 1, forKey: UtilityTabTarget.requestKey)
            defaults.set(UtilityTabTarget.browser, forKey: UtilityTabTarget.key)
            defaults.set(true, forKey: UtilityTabTarget.visibilityKey)
        }
    }

    /// The first visit can mount the browser after its request was published.
    public static func takePendingBrowserAddress() -> String? {
        defer { pendingBrowserAddress = nil }
        return pendingBrowserAddress
    }

    /// Opens a link only when it is a web link, ignoring anything
    /// else so a bare file path a terminal detected under the cursor
    /// never reaches the system opener, which handed it to Finder for
    /// a "-50" dialog. Returns whether it opened.
    @discardableResult
    @preconcurrency
    @MainActor
    public static func openWeb(
        _ address: String, inExternalBrowser: Bool = NSEvent.modifierFlags.contains(.command),
    ) -> Bool {
        guard address.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil,
              let url = URL(string: address), isWeb(url)
        else {
            return false
        }

        open(url.absoluteString, inExternalBrowser: inExternalBrowser)
        return true
    }

    // MARK: Private

    private static var pendingBrowserAddress: String?

    /// Whether a link has a web scheme and a host, the only shape
    /// either browser can open.
    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }
}

// MARK: - FileOpener

/// Opens files: in the built-in editor by default, in an external
/// editor when the command key is held. The built-in request lands
/// on the shared keys; the window routes it to the centre or side
/// editor and reveals whichever it picked. The external command
/// comes from the `externalEditorCommand` default (space-separated
/// argv), falling back to the system's default application.
public enum FileOpener {
    // MARK: Public

    /// Runs the external editor command on absolute paths: a
    /// worktree's root, or the root and then a file in it, which an
    /// editor that takes a folder opens in that worktree's window.
    /// Reports a command that fails, such as one not found on the path.
    /// Returns whether there was a command to run.
    @discardableResult
    @preconcurrency
    @MainActor
    public static func openInExternalEditor(_ absolutePaths: String...) -> Bool {
        let argv = (UserDefaults.standard.string(forKey: AppSettings.externalEditorKey) ?? "")
            .split(separator: " ")
            .map(String.init)
        guard argv.isEmpty == false else {
            return false
        }

        Task {
            let detail: String
            do {
                let result = try await FoundationProcessRunner().run(
                    argv + absolutePaths, workingDirectory: nil, environment: [:],
                )
                guard result.succeeded == false else {
                    return
                }

                detail = String(result.status) + ": "
                    + (result.standardError.isEmpty ? result.standardOutput : result.standardError)
            } catch {
                detail = error.localizedDescription
            }
            ErrorLog.shared.report(
                "The external editor `" + argv.joined(separator: " ") + "` could not open "
                    + (absolutePaths.last ?? "") + " (" + detail + ")",
            )
        }
        return true
    }

    /// Shows a file that belongs to no worktree in whichever one is
    /// on screen: `sanductor` can be handed anything readable, and
    /// refusing it would be less useful than showing it.
    @preconcurrency
    @MainActor
    public static func open(absolutePath: String, line: Int?, worktreePath: String) {
        let defaults = UserDefaults.standard
        defaults.set(absolutePath, forKey: "editorFilePath")
        defaults.set(line ?? 0, forKey: "editorFileLine")
        defaults.set(worktreePath, forKey: "editorFileWorktree")
        defaults.set(defaults.integer(forKey: "editorFileRequest") + 1, forKey: "editorFileRequest")
    }

    /// Routes a worktree-relative file by the command key. Paths
    /// that resolve outside the worktree are refused: a hostile
    /// repository could put `../` segments in a diff path. A plain
    /// click for a worktree other than `showingIn`, the one on screen,
    /// opens the file there by its absolute path: a request for
    /// another worktree waits unseen until that one is selected.
    @preconcurrency
    @MainActor
    public static func open(
        relativePath: String,
        line: Int?,
        worktreePath: String,
        showingIn shownPath: String? = nil,
    ) {
        guard let absolute = safePath(relativePath: relativePath, worktreePath: worktreePath) else {
            return
        }
        guard NSEvent.modifierFlags.contains(.command) else {
            if let shownPath, shownPath != worktreePath {
                open(absolutePath: absolute, line: line, worktreePath: shownPath)
                return
            }

            let defaults = UserDefaults.standard
            defaults.set(relativePath, forKey: "editorFilePath")
            defaults.set(line ?? 0, forKey: "editorFileLine")
            defaults.set(worktreePath, forKey: "editorFileWorktree")
            defaults.set(defaults.integer(forKey: "editorFileRequest") + 1, forKey: "editorFileRequest")
            return
        }

        if openInExternalEditor(worktreePath, absolute) == false {
            NSWorkspace.shared.open(URL(filePath: absolute))
        }
    }

    // MARK: Internal

    /// The resolved path, but only when it stays inside the worktree.
    static func safePath(relativePath: String, worktreePath: String) -> String? {
        guard relativePath.hasPrefix("/") == false else {
            return nil
        }

        let base = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        let target = URL(fileURLWithPath: worktreePath + "/" + relativePath).standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/") ? target : nil
    }
}
