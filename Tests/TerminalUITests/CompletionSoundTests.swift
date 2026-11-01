import Foundation
@testable import TerminalUI
import Testing

/// The completion chime's sound listing, its audio-only filter and
/// its silence through sleep.
struct CompletionSoundTests {
    @Test
    func `the system listing offers the default chime`() {
        let sounds = CompletionSound.systemSounds()

        #expect(sounds.contains { $0.path == CompletionSound.defaultPath })
        #expect(sounds.contains { $0.name == "Glass" })
    }

    @Test
    func `every listed sound is a playable audio type`() {
        for sound in CompletionSound.systemSounds() {
            #expect(CompletionSound.isPlayable(sound.path), "\(sound.path) should be audio")
        }
    }

    @Test
    func `only audio file types pass the filter`() {
        #expect(CompletionSound.isPlayable("Glass.aiff"))
        #expect(CompletionSound.isPlayable("ding.wav"))
        #expect(CompletionSound.isPlayable("chime.m4a"))
        #expect(CompletionSound.isPlayable("notes.txt") == false)
        #expect(CompletionSound.isPlayable("movie.mov") == false)
        #expect(CompletionSound.isPlayable("no-extension") == false)
    }

    @Test
    func `custom sounds are never opened during background playback`() throws {
        let path = URL(filePath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-scratch/sound-" + UUID().uuidString + ".aiff")
        defer { try? FileManager.default.removeItem(at: path) }
        try FileManager.default.copyItem(atPath: CompletionSound.defaultPath, toPath: path.path)
        #expect(CompletionSound.play(path: path.path) == false)
    }

    @Test
    func `an imported sound survives source removal and unused copies are pruned`() throws {
        let root = URL(filePath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-scratch/sounds-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.aiff")
        try FileManager.default.copyItem(atPath: CompletionSound.defaultPath, toPath: source.path)
        let store = NotificationSoundStore(directory: root.appendingPathComponent("imported"))
        #expect(store.needsImport(source.path))
        try store.importFile(at: source.path)
        try FileManager.default.removeItem(at: source)
        let cached = URL(filePath: store.playbackPath(for: source.path))
        #expect(try Data(contentsOf: cached) == Data(contentsOf: URL(filePath: CompletionSound.defaultPath)))
        #expect(store.needsImport(source.path) == false)
        store.removeUnused(keeping: [source.path])
        #expect(FileManager.default.fileExists(atPath: cached.path))
        store.removeUnused(keeping: [])
        #expect(FileManager.default.fileExists(atPath: cached.path) == false)
    }

    @Test
    func `a machine going to sleep is played nothing at all`() {
        // Sleep is announced before it happens: a chime started now
        // is the one nobody hears, and the one the old alert path
        // brought back looping.
        CompletionSound.beginSleeping()
        #expect(CompletionSound.play(path: CompletionSound.defaultPath) == false)

        // Waking gives the chimes back.
        CompletionSound.endSleeping()
        #expect(CompletionSound.play(path: CompletionSound.defaultPath))
        #expect(CompletionSound.play(path: "") == false)
        #expect(CompletionSound.play(path: "/nowhere/missing.aiff") == false)
    }
}
