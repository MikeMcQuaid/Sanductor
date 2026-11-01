import Foundation

/// Streaming gzip keeps large transcripts out of the app's memory.
enum BackupCompression {
    // MARK: Internal

    @concurrent
    static func write(source: String, destination: String) async throws {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: source)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let temporary = destination + ".compression-" + UUID().uuidString
        defer { try? manager.removeItem(atPath: temporary) }
        let result = try await FoundationProcessRunner().run(
            [
                "/bin/sh", "-c",
                "/usr/bin/nice -n 10 /usr/bin/gzip -1 -n -c -- \"$1\" > \"$2\"",
                "gzip", source, temporary,
            ],
            workingDirectory: "/",
            environment: [:],
            outputLimit: diagnosticLimit,
        )
        guard result.succeeded else {
            throw CommandError(command: "gzip backup", result: result)
        }

        if let modified = attributes[.modificationDate] {
            try manager.setAttributes([.modificationDate: modified], ofItemAtPath: temporary)
        }
        guard unsafe rename(temporary, destination) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: Private

    private static let diagnosticLimit = 16_384
}
