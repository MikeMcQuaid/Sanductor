import AppKit
import SanductorDomain
import UniformTypeIdentifiers

/// Reads the pasteboard while it still belongs to the drop or paste.
public enum AttachmentPasteboard {
    /// Prefer actual files, then lossless screenshot formats, then other image representations.
    public static let types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff] + NSImage.imageTypes
        .filter { type in
            type != UTType.png.identifier && type != UTType.tiff.identifier
                && UTType(type)?.preferredFilenameExtension != nil
        }
        .map(NSPasteboard.PasteboardType.init(rawValue:))

    /// Captures file URLs or encoded image bytes before the pasteboard changes hands.
    public static func attachments(
        from board: NSPasteboard, type requested: NSPasteboard.PasteboardType? = nil,
    ) -> [PromptAttachment] {
        guard let type = requested ?? board.availableType(from: types) else {
            return []
        }

        if type == .fileURL {
            // swiftlint:disable:next legacy_objc_type - NSPasteboard takes a class for each reading type.
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            return (urls as? [URL] ?? []).map(PromptAttachment.file)
        }
        guard let suffix = UTType(type.rawValue)?.preferredFilenameExtension,
              let data = board.data(forType: type)
        else {
            return []
        }

        return [.image(data, named: "image." + suffix)]
    }
}
