import Darwin
import Foundation

/// A host-designated plist or its directly linked target, updated atomically under a directory lock.
struct SettingsFile {
    // MARK: Lifecycle

    init(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        // Only the link in the user's private directory designates a trusted destination name.
        let directory = unsafe open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard directory >= 0 else {
            throw SessionServiceError("Cannot open settings directory " + parent.path)
        }

        defer { close(directory) }
        if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            destination = URL(filePath: link, relativeTo: parent).absoluteURL
        } else {
            destination = url
        }
    }

    // MARK: Internal

    let destination: URL

    // swiftlint:disable:next discouraged_optional_collection - A missing file needs its initial contents.
    func update(_ update: ([String: NSObject]?) throws -> [String: NSObject]) throws {
        let directory = destination.deletingLastPathComponent().path
        let folder = unsafe open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard folder >= 0 else {
            throw SessionServiceError("Cannot open settings directory " + directory)
        }

        defer { close(folder) }
        guard flock(folder, LOCK_EX | LOCK_NB) == 0 else {
            throw SessionServiceError("Settings directory is busy")
        }

        // A child launched during this write may still hold the descriptor until exec.
        defer { flock(folder, LOCK_UN) }
        let name = destination.lastPathComponent
        let existing = try SandboxFile.read(name, byteLimit: Self.byteLimit, relativeTo: folder).map { data in
            guard let values = try unsafe PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: NSObject]
            else {
                throw SessionServiceError("Expected a dictionary in " + destination.path)
            }

            return values
        }
        let values = try update(existing)
        if existing != values {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            guard data.count <= Self.byteLimit else {
                throw SessionServiceError("Settings file is too large")
            }

            try SandboxFile.replace(name, in: folder, with: data, mode: 0o600)
        }
    }

    // MARK: Private

    private static let byteLimit = 1_048_576
}
