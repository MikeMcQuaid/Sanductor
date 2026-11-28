import QuickLook
import SanductorData
import SanductorDomain
import SwiftUI
import TerminalUI

/// The live terminal and its Reader share one file preview.
struct AgentOutputLinks: ViewModifier {
    // MARK: Internal

    let service: SessionService
    let agent: AgentKind?
    let path: String
    let active: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.agentOutputLink, $requested)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == nil || url.isFileURL {
                    requested = .destination(url)
                } else {
                    openURL(url)
                }
                return .handled
            })
            .task(id: active ? requested : nil) {
                await followLink()
            }
            .quickLookPreview($preview)
            .onChange(of: preview) { previous, _ in
                if let previous {
                    try? FileManager.default.removeItem(at: previous.deletingLastPathComponent())
                }
            }
            .onChange(of: active) {
                if active == false {
                    requested = nil
                    preview = nil
                }
            }
            .onDisappear {
                if let preview {
                    try? FileManager.default.removeItem(at: preview.deletingLastPathComponent())
                }
            }
    }

    // MARK: Private

    @Environment(\.openURL)
    private var openURL
    @State private var requested: AgentOutputLink?
    @State private var preview: URL?

    private func followLink() async {
        guard active, let requested else {
            return
        }

        var isCurrent: Bool {
            Task.isCancelled == false && self.requested == requested
        }
        defer {
            if isCurrent {
                self.requested = nil
            }
        }
        let url: URL
        switch requested {
        case let .destination(destination):
            url = destination

        case let .label(label, externalBrowser):
            guard let transcript = await service.liveTranscript(agent: agent, in: path),
                  let destination = await service.linkDestination(
                      label: label, transcript: URL(filePath: transcript.path),
                  ),
                  isCurrent
            else {
                return
            }

            if destination.scheme != nil, destination.isFileURL == false {
                if LinkOpener.openWeb(destination.absoluteString, inExternalBrowser: externalBrowser) == false {
                    ErrorLog.shared.report("Not a web link, so not opened: " + destination.absoluteString)
                }
                return
            }
            url = destination
        }
        do {
            let copy = try await service.previewFile(url, in: path)
            if isCurrent {
                preview = copy
            } else {
                try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
            }
        } catch {
            if isCurrent {
                ErrorLog.shared.report(error.localizedDescription)
            }
        }
    }
}
