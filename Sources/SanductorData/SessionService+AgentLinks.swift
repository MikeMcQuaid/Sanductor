import Foundation
import Markdown
import SanductorDomain

// MARK: - MatchingLinks

private struct MatchingLinks: MarkupWalker {
    let label: String
    var destinations: Set<String> = []

    mutating func visitLink(_ link: Link) {
        if link.plainText == label, let destination = link.destination {
            destinations.insert(destination)
        }
    }
}

public extension SessionService {
    /// Codex can draw a local link as underlined text without an OSC 8 target.
    @concurrent
    func linkDestination(label: String, transcript: URL) async -> URL? {
        // Filter out tool output without guessing how Markdown spells the label.
        // The reply marker can precede or follow its prose in a JSON record.
        let reply = #""(?:assistant|agent_message)""#
        let prose = #""(?:text|content|message)"\s*:\s*".*(?:\[|<|\\u)"#
        let pattern = reply + ".*" + prose + "|" + prose + ".*" + reply
        guard label.isEmpty == false, let matches = try? await processes.run(
            ["rg", "--no-config", "--no-heading", "--no-line-number", "--", pattern, transcript.path],
            workingDirectory: nil,
            environment: [:],
            outputLimit: Self.linkMatchByteLimit,
        ), matches.succeeded else {
            return nil
        }

        var entries = [TranscriptEntry]()
        TranscriptParser.append(matches.standardOutput, to: &entries)
        var links = MatchingLinks(label: label)
        for entry in entries where entry.role == .assistant {
            links.visit(Document(parsing: entry.text))
        }
        guard links.destinations.count == 1, let destination = links.destinations.first else {
            return nil
        }

        return URL(string: destination)
    }

    /// Quick Look receives a private snapshot of a regular workspace file.
    @concurrent
    func previewFile(_ link: URL, in worktreePath: String) async throws -> URL {
        guard link.scheme == nil || link.isFileURL, (link.host ?? "").isEmpty || link.host == "localhost",
              link.query == nil, link.path.isEmpty == false, link.path.utf8.contains(0) == false
        else {
            throw SessionServiceError("This link does not name a local file.")
        }

        let base = URL(filePath: worktreePath, directoryHint: .isDirectory)
        let file = try Self.canonicalFile(at: URL(filePath: link.path, relativeTo: base).path)
        guard try file.path.hasPrefix(Self.canonicalFile(at: paths.sharedWorkspace).path + "/") else {
            throw SessionServiceError("The linked file is outside the shared workspace.")
        }

        let parent = unsafe open(file.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY)
        guard parent >= 0 else {
            throw SessionServiceError("Cannot read the linked file’s directory.")
        }

        defer { close(parent) }
        guard let data = try SandboxFile.read(
            file.lastPathComponent, byteLimit: Self.previewByteLimit, relativeTo: parent,
        )
        else {
            throw SessionServiceError("The linked file is missing: " + file.path)
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700],
        )
        let copy = directory.appending(path: file.lastPathComponent)
        do {
            try data.write(to: copy)
            return copy
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static let linkMatchByteLimit = 8_388_608
    private static let previewByteLimit = 67_108_864

    /// Foundation can shorten a resolved /private/var path back to the /var symlink.
    private static func canonicalFile(at path: String) throws -> URL {
        guard let resolved = unsafe realpath(path, nil) else {
            throw SessionServiceError("Cannot find the linked file: " + path)
        }

        defer { unsafe free(resolved) }
        return unsafe URL(filePath: String(cString: resolved))
    }
}
