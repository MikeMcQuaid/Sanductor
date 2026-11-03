import Foundation
import Markdown

/// Protect code and Markdown links before an HTML parser sees their brackets.
public struct MarkdownHTMLCode {
    // MARK: Lifecycle

    /// Replaces parsed code and links with reversible placeholders.
    public init(_ text: String, htmlEmphasis: Bool = false, transform: (any Markup) -> String? = { _ in nil }) throws {
        let lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        var ranges = [(Range<String.Index>, String?)]()
        func visit(_ node: any Markup) throws {
            let replacement = transform(node)
            let bold = htmlEmphasis && node is Strong && node.children.contains { $0 is InlineHTML }
            if replacement != nil || node is CodeBlock || node is InlineCode || node is Link
                || node is Markdown.Image || bold,
               let range = node.range
            {
                guard let start = Self.sourceIndex(at: range.lowerBound, in: text, lines: lines),
                      let end = Self.sourceIndex(at: range.upperBound, in: text, lines: lines),
                      start <= end, (ranges.last?.0.upperBound ?? text.startIndex) <= start
                else {
                    throw InvalidSourceRange()
                }

                if bold, replacement == nil {
                    guard let openingEnd = text.index(start, offsetBy: Self.boldDelimiterLength, limitedBy: end),
                          let closingStart = text.index(end, offsetBy: -Self.boldDelimiterLength, limitedBy: openingEnd)
                    else {
                        throw InvalidSourceRange()
                    }

                    // Preserve parsed emphasis when removing an icon exposes leading whitespace.
                    ranges.append((start ..< openingEnd, "<strong>"))
                    try node.children.forEach(visit)
                    ranges.append((closingStart ..< end, "</strong>"))
                } else {
                    ranges.append((start ..< end, replacement))
                }
            } else {
                try node.children.forEach(visit)
            }
        }
        try visit(Document(parsing: text))
        var escaped = text
        var saved = [(String, String)]()
        let prefix = "SANDUCTOR" + UUID().uuidString
        for (index, entry) in ranges.reversed().enumerated() {
            let (range, replacement) = entry
            if let replacement {
                escaped.replaceSubrange(range, with: replacement)
                continue
            }
            let key = prefix + String(index) + "END"
            saved.append((key, String(text[range])))
            escaped.replaceSubrange(range, with: key)
        }
        source = escaped
        replacements = saved
    }

    // MARK: Public

    /// Text safe to pass through an HTML parser.
    public let source: String

    /// Restores protected content verbatim.
    public func restore(_ text: String) -> String {
        replacements.reduce(text) { $0.replacing($1.0, with: $1.1) }
    }

    // MARK: Private

    private struct InvalidSourceRange: Error {}

    private static let boldDelimiterLength = 2

    private let replacements: [(String, String)]

    private static func sourceIndex(at location: SourceLocation, in text: String, lines: [Substring]) -> String.Index? {
        guard location.line > 0, location.line <= lines.count, location.column > 0 else {
            return nil
        }

        let line = lines[location.line - 1].utf8
        guard let index = line.index(
            line.startIndex, offsetBy: location.column - 1, limitedBy: line.endIndex,
        ) else {
            return nil
        }

        return String.Index(index, within: text)
    }
}
