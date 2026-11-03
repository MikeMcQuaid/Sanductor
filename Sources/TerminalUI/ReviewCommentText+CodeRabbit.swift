import Foundation
import Markdown
import SwiftSoup

extension ReviewCommentText {
    static func receiptReplacements(_ text: String) -> [SourceRange: String] {
        let nodes = Array(Document(parsing: text).children)
        var replacements = [SourceRange: String]()
        for (index, node) in nodes.enumerated() {
            guard let heading = node as? Heading,
                  heading.plainText.range(
                      of: #"(?i)^(?:usage[- ]based\s+)?review\s+receipt$"#, options: .regularExpression,
                  ) != nil,
                  let range = node.range
            else {
                continue
            }

            let receipt = nodes.dropFirst(index + 1).prefix { child in
                child is UnorderedList || (child is BlockQuote
                    && (child.child(at: 0) as? Paragraph)?.plainText
                    .range(of: billingPattern, options: .regularExpression) != nil)
            }
            guard receipt.isEmpty == false else {
                continue
            }

            replacements[range] = "<details><summary>Usage-based review receipt</summary>\n\n"
                + formattedBlocks(receipt) + "\n\n</details>"
            for child in receipt {
                if let childRange = child.range {
                    replacements[childRange] = ""
                }
            }
        }
        return replacements
    }

    static func codeRabbitReplacement(_ node: any Markup) -> String? {
        if let paragraph = node as? Paragraph,
           paragraph.plainText.range(
               of: #"(?is)^(?:you can disable (?:this|the) status message\b|use (?:the|a) checkbox\b.*\bretry\b)"#,
               options: .regularExpression,
           ) != nil
        {
            return ""
        }
        if let item = node as? ListItem, item.checkbox != nil,
           let paragraph = item.child(at: 0) as? Paragraph,
           paragraph.children.contains(where: { child in
               (child as? InlineHTML)?.rawHTML.range(of: #"(?i)\"checkboxId\"\s*:"#, options: .regularExpression) != nil
           }),
           paragraph.plainText.range(
               of: #"(?i)\b(?:trigger|retry|request|run)\s+(?:(?:a|the)\s+)?review\s*$"#,
               options: .regularExpression,
           ) != nil,
           paragraph.children.contains(where: { $0 is InlineCode }) == false
        {
            return ""
        }
        guard let quote = node as? BlockQuote, let first = quote.child(at: 0) as? Paragraph else {
            return nil
        }

        let children = Array(quote.children)
        if first.plainText.range(of: billingPattern, options: .regularExpression) != nil {
            return "<details><summary>Usage-based billing</summary>\n\n"
                + formattedBlocks(children)
                .replacingOccurrences(of: #"(?i)^\[!\w+\]\s*"#, with: "", options: .regularExpression)
                + "\n\n</details>"
        }
        guard first.plainText.range(of: #"(?i)^\[!\w+\]$"#, options: .regularExpression) != nil else {
            return nil
        }

        if let heading = quote.child(at: 1) as? Heading {
            let body = formattedBlocks(children.dropFirst(heading.indexInParent + 1))
            let cleaned = try? protectedMarkdown(body, isCodeRabbit: true)
            return "<details><summary>" + first.plainText
                .trimmingCharacters(in: CharacterSet(charactersIn: "[!]"))
                .capitalized
                + ": " + Entities.escape(formattedBlocks([Paragraph(heading.inlineChildren)])) + "</summary>\n\n"
                + (cleaned.map { $0.restore($0.source) } ?? body) + "\n\n</details>"
        }
        let body = formattedBlocks(children.dropFirst())
        if body.range(of: #"(?is)^\s*<details(?:\s|>).*?</details>\s*$"#, options: .regularExpression) != nil {
            return body
        }
        return nil
    }

    static func findingRows(in document: SwiftSoup.Document, source: String) throws -> String {
        var result = source
        for link in try document.select("a") {
            guard let badge = try link.select("img").first(),
                  try link.attr("href").range(of: #"(?i)#discussion[_-]"#, options: .regularExpression) != nil
                  || badge.attr("alt").range(
                      of: #"(?i)^(?:critical|major|minor|trivial)$"#, options: .regularExpression,
                  ) != nil,
                  let range = try result.range(of: link.outerHtml(), options: .literal)
            else {
                continue
            }

            try badge.attr("alt", badge.attr("alt") + " ›")
            try result.replaceSubrange(range, with: "\n- " + link.outerHtml())
        }
        return result
    }

    private static func formattedBlocks(_ nodes: some Sequence<any Markup>) -> String {
        Markdown.Document(nodes.compactMap { $0 as? any BlockMarkup }).format()
    }
}
