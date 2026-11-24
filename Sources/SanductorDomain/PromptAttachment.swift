import Foundation

/// A file or the original bytes of an image from a drop or paste.
public enum PromptAttachment: Sendable {
    case file(URL)
    case image(Data, named: String)
}
