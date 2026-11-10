import Foundation
@testable import SanductorData
import Testing

// MARK: - PromptPayloadRaceTests

struct PromptPayloadRaceTests {
    @Test(arguments: [false, true])
    func `cleanup rejects symlink ancestors of the prompt directory`(tracked: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let file = world.paths.promptsDirectory + "/prompt-" + UUID().uuidString + ".md"
        let manager = FileManager.default
        try manager.createDirectory(atPath: world.paths.promptsDirectory, withIntermediateDirectories: true)
        try "keep".write(toFile: file, atomically: true, encoding: .utf8)
        if tracked {
            try PromptPayload.adoptExisting(paths: world.paths, store: store)
        }
        try manager.moveItem(atPath: world.paths.sanductorDirectory, toPath: world.root + "/outside")
        try manager.createSymbolicLink(
            atPath: world.paths.sanductorDirectory, withDestinationPath: world.root + "/outside",
        )
        let later = Date().addingTimeInterval(10 * 86_400)
        if tracked {
            PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: later)
            #expect(store.load().temporaryPromptFiles[file] != nil)
        } else {
            PromptPayload.cleanTemporaryFiles(paths: world.paths, store: store, protectedPaths: [], now: later)
        }
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "keep")
    }

    @Test(arguments: [false, true])
    func `recent directories still expire old descendants`(tracked: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let folder = world.paths.sharedWorkspace + "/tmp/drop-" + UUID().uuidString + "-folder"
        let manager = FileManager.default
        try manager.createDirectory(atPath: folder + "/nested", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: folder + "/old-empty", withIntermediateDirectories: true)
        try "old".write(toFile: folder + "/nested/old.txt", atomically: true, encoding: .utf8)
        let now = Date()
        for path in [folder, folder + "/nested", folder + "/nested/old.txt", folder + "/old-empty"] {
            try manager.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 86_400)], ofItemAtPath: path)
        }
        if tracked {
            try PromptPayload.adoptExisting(paths: world.paths, store: store)
        }
        for path in [folder, folder + "/nested"] {
            try manager.setAttributes([.modificationDate: now], ofItemAtPath: path)
        }
        if tracked {
            PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: now)
            #expect(store.load().temporaryPromptFiles[folder] != nil)
        } else {
            PromptPayload.cleanTemporaryFiles(paths: world.paths, store: store, protectedPaths: [], now: now)
        }
        #expect(manager.fileExists(atPath: folder + "/nested/old.txt") == false)
        #expect(manager.fileExists(atPath: folder + "/old-empty") == false)
        #expect(manager.fileExists(atPath: folder + "/nested"))
    }

    @Test(arguments: [false, true], [0, 1, 2])
    func `directory swaps cannot redirect cleanup outside its tree`(tracked: Bool, level: Int) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let folder = world.paths.sharedWorkspace + "/tmp/drop-" + UUID().uuidString + "-folder"
        let swap = [world.paths.sharedWorkspace + "/tmp", folder, folder + "/nested"][level]
        let outside = world.root + "/outside"
        let sentinel = outside + String((folder + "/nested/old.txt").dropFirst(swap.count))
        let now = Date()
        for file in [folder + "/nested/old.txt", sentinel] {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: file).deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try "keep outside".write(toFile: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-10 * 86_400)], ofItemAtPath: file,
            )
        }
        for path in [folder, folder + "/nested"] {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-10 * 86_400)], ofItemAtPath: path,
            )
        }
        if tracked {
            try PromptPayload.adoptExisting(paths: world.paths, store: store)
        }
        let reader = DirectorySwapFileReader(swapped: swap, moved: world.root + "/moved", outside: outside)
        if tracked {
            PromptPayload.clean(
                paths: world.paths, store: store, sessions: [], protectedPaths: [], now: now, reader: reader,
            )
        } else {
            PromptPayload.cleanTemporaryFiles(
                paths: world.paths, store: store, protectedPaths: [], now: now, reader: reader,
            )
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: swap) == outside)
        #expect(FileManager.default.fileExists(atPath: sentinel))
    }

    @Test(arguments: [false, true], [false, true])
    func `cleanup preserves files created during expiry checks`(tracked: Bool, replacingFile: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let store = MetadataStore(file: world.paths.metadataFile)
        let folder = world.paths.sharedWorkspace + "/tmp/drop-" + UUID().uuidString + "-folder"
        let file = folder + "/old.txt"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try "old".write(toFile: file, atomically: true, encoding: .utf8)
        let now = Date()
        for path in [file, folder] {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-10 * 86_400)], ofItemAtPath: path,
            )
        }
        if tracked {
            try PromptPayload.adoptExisting(paths: world.paths, store: store)
        }
        let reader = ConcurrentWriterFileReader(file: file, replacingFile: replacingFile)
        if tracked {
            PromptPayload.clean(
                paths: world.paths, store: store, sessions: [], protectedPaths: [], now: now, reader: reader,
            )
            #expect(store.load().temporaryPromptFiles[folder] != nil)
        } else {
            PromptPayload.cleanTemporaryFiles(
                paths: world.paths, store: store, protectedPaths: [], now: now, reader: reader,
            )
        }
        let fresh = (replacingFile ? file : folder) + "/fresh.txt"
        #expect(FileManager.default.fileExists(atPath: fresh))
        if FileManager.default.fileExists(atPath: fresh) {
            #expect(try String(contentsOfFile: fresh, encoding: .utf8) == "new work")
        }
        let later = now.addingTimeInterval(11 * 86_400)
        if tracked {
            PromptPayload.clean(paths: world.paths, store: store, sessions: [], protectedPaths: [], now: later)
            #expect(store.load().temporaryPromptFiles[folder] == nil)
        } else {
            PromptPayload.cleanTemporaryFiles(paths: world.paths, store: store, protectedPaths: [], now: later)
        }
        #expect(FileManager.default.fileExists(atPath: folder) == false)
    }
}

// MARK: - DirectorySwapFileReader

private struct DirectorySwapFileReader: TemporaryFileReading {
    let swapped: String
    let moved: String
    let outside: String

    func attributes(_ name: String, relativeTo directory: Int32) throws -> stat? {
        try LocalTemporaryFileReader().attributes(name, relativeTo: directory)
    }

    func names(in directory: Int32) throws -> [String] {
        let names = try LocalTemporaryFileReader().names(in: directory)
        if names.contains("old.txt") {
            try FileManager.default.moveItem(atPath: swapped, toPath: moved)
            try FileManager.default.createSymbolicLink(atPath: swapped, withDestinationPath: outside)
        }
        return names
    }
}

// MARK: - ConcurrentWriterFileReader

private struct ConcurrentWriterFileReader: TemporaryFileReading {
    let file: String
    let replacingFile: Bool

    func attributes(_ name: String, relativeTo directory: Int32) throws -> stat? {
        let attributes = try LocalTemporaryFileReader().attributes(name, relativeTo: directory)
        if name == URL(fileURLWithPath: file).lastPathComponent {
            let folder = replacingFile ? file : URL(fileURLWithPath: file).deletingLastPathComponent().path
            if replacingFile {
                try FileManager.default.removeItem(atPath: file)
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
            }
            try "new work".write(toFile: folder + "/fresh.txt", atomically: true, encoding: .utf8)
        }
        return attributes
    }

    func names(in directory: Int32) throws -> [String] {
        try LocalTemporaryFileReader().names(in: directory)
    }
}
