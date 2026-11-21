import Foundation
import SanductorDomain

public extension RemoteHerdr {
    /// Stream the selected agent's JSONL directly from the sandbox over SSH.
    func followTranscript(
        at path: String, update: @Sendable ([TranscriptEntry]) async -> Void,
    ) async throws {
        guard path.hasPrefix("/"), path.hasSuffix(".jsonl") else {
            throw RemoteError("The Mac has not published a transcript for this agent.")
        }

        let size = try await connection.execute(configuration.command(["/usr/bin/stat", "-Lf", "%z", path]))
        guard let fileSize = Int(size.trimmingCharacters(in: .whitespacesAndNewlines)), fileSize >= 0 else {
            throw RemoteError("Could not read the agent's transcript size.")
        }

        var window = RecentTranscript(fileSize: fileSize)
        try Task.checkCancellation()
        let stream = try await followFile(
            #"test -r "$1" || exit 1"#, options: "-c +\(window.offset + 1) -f", arguments: [path],
        )
        defer { stream.close() }
        try await withTaskCancellationHandler {
            if fileSize == 0 {
                await update([])
            }
            for try await packet in stream.output {
                try Task.checkCancellation()
                if try window.append(packet) {
                    await update(window.entries)
                }
            }
        } onCancel: {
            stream.close()
        }
    }

    /// Uses the same agent-only submission as the Mac, without a terminal takeover.
    func reply(_ reply: ReaderReply, paneID: String) async throws {
        let output = try await connection.execute(configuration.command(["herdr"] + reply.arguments(paneID: paneID)))
        guard ReaderReply.wasSubmitted(output, to: paneID) else {
            throw RemoteError("herdr could not confirm the reply. Check the agent’s terminal before resending.")
        }
    }

    /// A non-PTY SSH channel closing delivers EOF on stdin. Reap even an idle tail on disconnect.
    internal func followFile(_ setup: String, options: String, arguments: [String] = []) async throws -> SSHCommand {
        let script = setup + "\n/usr/bin/tail " + options + #" "$1" &"# + "\n" + #"""
        follower=$!
        trap 'kill "$follower" 2>/dev/null || true' EXIT
        cat >/dev/null
        """#
        return try await connection.open(configuration.command(["/bin/sh", "-c", script, "sanductor"] + arguments))
    }
}
