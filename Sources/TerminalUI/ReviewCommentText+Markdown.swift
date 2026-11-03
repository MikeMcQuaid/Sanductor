import Foundation
import Markdown
import SanductorData
import SwiftSoup

extension ReviewCommentText {
    static let billingPattern = #"(?i)^(?:\[!\w+\]\s*)?this\s+review\s+(?:was|has\s+been)\s+completed\s+with\s+"#
        + #"usage[- ]based\s+(?:billing|reviews?)\b"#
    private static let compactHeadingLevel = 3
    private static let thankYou = #"(?i)^thanks?\s+for\s+using\s+CodeRabbit!"#

    static func protectedMarkdown(_ text: String, isCodeRabbit: Bool) throws -> MarkdownHTMLCode {
        let receipts = isCodeRabbit ? receiptReplacements(text) : [:]
        let transformed = try MarkdownHTMLCode(text) { node in
            if let range = node.range, let replacement = receipts[range] {
                return replacement
            }
            if isCodeRabbit, var heading = node as? Heading, heading.level < compactHeadingLevel {
                heading.level = compactHeadingLevel
                return Markdown.Document([heading]).format()
            }
            if isCodeRabbit, let replacement = codeRabbitReplacement(node) {
                return replacement
            }
            if isCodeRabbit, let paragraph = node as? Paragraph,
               paragraph.plainText.range(of: thankYou, options: .regularExpression) != nil,
               paragraph.children.contains(where: { $0 is InlineCode }) == false
            {
                return ""
            }
            return nil
        }
        return try MarkdownHTMLCode(transformed.restore(transformed.source))
    }

    static func withoutNotices(_ source: String) -> String {
        do {
            let document = try SwiftSoup.parseBodyFragment(source)
            // Pretty printing would serialise entities instead of reusing source ranges.
            document.outputSettings().prettyPrint(pretty: false)
            var result = source.replacingOccurrences(
                of: #"(?is)<!--\s*verify_invitation_start\s*-->.*?<!--\s*verify_invitation_end\s*-->"#,
                with: "",
                options: .regularExpression,
            )
            for element in try document.select("details, blockquote, p, sub, sup") {
                let summary = try element.children().first { $0.tagName() == "summary" }?.text() ?? ""
                let share = summary.range(of: #"(?i)^(?:❤️?\s*)?share$"#, options: .regularExpression) != nil
                let opening = try element.children().first()?.tagName() == "p"
                    ? element.children().first()?.text() ?? "" : element.ownText()
                let notice = try element.tagName() == "blockquote" && element.select("pre, code").isEmpty()
                    && opening.range(of: billingPattern, options: .regularExpression) != nil
                let promotion = try ["p", "sub", "sup"].contains(element.tagName())
                    && element.select("pre, code").isEmpty()
                    && element.text().range(of: thankYou, options: .regularExpression) != nil
                if share || notice || promotion,
                   let range = try result.range(of: element.outerHtml(), options: .literal)
                {
                    try result.replaceSubrange(range, with: notice
                        ? "<details><summary>Usage-based billing</summary>" + (element.html()) + "</details>" : "")
                }
            }
            return try findingRows(in: document, source: result)
        } catch {
            return source
        }
    }
}
