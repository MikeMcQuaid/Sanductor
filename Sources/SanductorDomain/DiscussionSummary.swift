/// A discussion's canonical repository URL keeps organisation picks unambiguous.
public struct DiscussionSummary: ReferencedItem, Decodable, Hashable, Sendable {
    public let number: Int
    public let title: String
    public let url: String
    public let closed: Bool

    public var id: String {
        url
    }

    public var reference: String {
        "#" + String(number)
    }
}
