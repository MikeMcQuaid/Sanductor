import AppKit
import SanductorData
import SwiftUI

public extension EnvironmentValues {
    /// The stack and branch that own feedback copied from this pane.
    @Entry var feedbackStackPrefix = ""
}

// MARK: - ClipboardCopy

/// Holds the clipboard generation from the start of an asynchronous copy.
public final class ClipboardCopy {
    // MARK: Lifecycle

    /// Captures ownership, optionally clearing stale contents before a fetch.
    public init(to pasteboard: NSPasteboard = .general, clearing: Bool = false) {
        self.pasteboard = pasteboard
        clearedBeforeReading = clearing
        changeCount = clearing ? pasteboard.clearContents() : pasteboard.changeCount
        Self.latest.setObject(self, forKey: pasteboard)
    }

    deinit {
        // The pasteboard table holds requests weakly.
    }

    // MARK: Public

    /// Whether this copy can still publish its result or report its failure.
    public var isCurrent: Bool {
        Self.latest.object(forKey: pasteboard) === self && pasteboard.changeCount == changeCount
    }

    /// Formats feedback off the UI thread and stages oversized prompts.
    @preconcurrency
    @discardableResult
    public func writePrompt(_ feedback: @escaping @Sendable () -> String) async -> Bool {
        await writeText {
            let text = feedback()
            guard text.utf8.count > PromptPayload.inlineByteLimit else {
                return text
            }

            let paths = WorkspacePaths.current()
            return try PromptPayload.prepare(text, paths: paths, store: MetadataStore(file: paths.metadataFile))
        }
    }

    /// Prepares plain text off the UI thread and honours a newer copy, even on failure.
    @preconcurrency
    @discardableResult
    public func writeText(_ preparing: @escaping @Sendable () throws -> String) async -> Bool {
        guard isCurrent else {
            return false
        }

        do {
            let text = try await Task.detached(operation: preparing).value
            return write { $0.setString(text, forType: .string) }
        } catch {
            if isCurrent {
                ErrorLog.shared.report("Could not prepare text for copying: " + error.localizedDescription)
            }
            return false
        }
    }

    /// Native selection copies are immediate unless their formatting could stall the editor.
    @preconcurrency
    public func writeSelection(_ text: String, formatting: @escaping @Sendable (String) -> String) {
        if text.utf8.count > PromptPayload.inlineByteLimit {
            Task {
                await writeText { formatting(text) }
            }
        } else {
            write { $0.setString(formatting(text), forType: .string) }
        }
    }

    // MARK: Internal

    @discardableResult
    func write(_ contents: (NSPasteboard) -> Bool) -> Bool {
        guard isCurrent else {
            return false
        }

        if clearedBeforeReading == false {
            pasteboard.clearContents()
        }
        return contents(pasteboard)
    }

    // MARK: Private

    /// Two in-flight copies can share a change count until one of them writes.
    private static let latest: NSMapTable<NSPasteboard, ClipboardCopy> = .weakToWeakObjects()

    private let pasteboard: NSPasteboard
    private let changeCount: Int
    private let clearedBeforeReading: Bool
}
