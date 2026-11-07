import Foundation
import Markdown
import SanductorDomain
import SwiftSoup
import Synchronization

/// File-anchored findings embedded in CodeRabbit's review summaries.
enum CodeRabbitOutsideDiff {
    // MARK: Internal

    static func threads(in events: [ReviewComment]) -> [ReviewThread] {
        guard let review = events.filter({ event in
            event.authorType == "Bot" && ReviewBot.codeRabbit.matches(event.author)
                && ["COMMENTED", "CHANGES_REQUESTED", "APPROVED"].contains(event.kind)
        })
        .max(by: { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }) else {
            return []
        }

        if let threads = cache.withLock({ $0[review] }) {
            return threads
        }
        var identities = Set<String>()
        let threads: [ReviewThread] = (try? parse(review).compactMap { finding in
            let protectedBody = try MarkdownHTMLCode(finding.body) { node in
                (node as? Markdown.Link)?.plainText.range(of: sourceLinkPattern, options: .regularExpression) != nil
                    ? "" : nil
            }
            let body = try MarkdownHTML(protectedBody.restore(protectedBody.source))
                .markdown
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = "coderabbit-outside-diff:" + LocalReviewInput.fingerprint(
                finding.path + "\n" + String(finding.line) + "\n" + body,
            )
            guard identities.insert(identity).inserted else {
                return nil
            }

            return ReviewThread(
                id: identity,
                path: finding.path,
                line: finding.line,
                isResolved: false,
                comments: [
                    ReviewThreadComment(author: review.author, body: finding.body, authorType: review.authorType),
                ],
                resolveID: "",
                outsideDiffReviewID: review.id,
            )
        }) ?? []
        cache.withLock { cached in
            if cached.count >= cacheLimit {
                cached = [:]
            }
            cached[review] = threads
        }
        return threads
    }

    // MARK: Private

    private struct Finding {
        let path: String
        let line: Int
        var body: String
    }

    private static let cacheLimit = 64
    private static let blobComponent = 3
    private static let sourcePathStart = 5
    private static let outsideDiffPattern = #"(?i)\boutside[-\s]+(?:the\s+)?diff\b"#
    private static let sourceLinkPattern = #"(?i)^(?:open|view)\s+(?:the\s+)?source(?:\s+(?:location|code))?$"#
    private static let cache: Mutex<[ReviewComment: [ReviewThread]]> = .init([:])

    private static func parse(_ review: ReviewComment) throws -> [Finding] {
        let protected = try MarkdownHTMLCode(review.body + "\n" + calloutDisclosures(review.body))
        let document = try SwiftSoup.parseBodyFragment(protected.source)
        document.outputSettings().prettyPrint(pretty: false)
        var findings = [Finding]()
        for details in try document.select("details") {
            guard let summary = details.children().first(where: { $0.tagName() == "summary" }) else {
                continue
            }

            if try summary.select("img").contains(where: { badge in
                try badge.attr("alt").range(of: outsideDiffPattern, options: .regularExpression) != nil
            }) {
                let body = try protected.restore(content(details))
                if let location = sourceLocation(Document(parsing: body)) {
                    findings.append(Finding(path: location.path, line: location.line, body: body))
                }
            } else if try summary.text().range(of: outsideDiffPattern, options: .regularExpression) != nil {
                let files = try details.select("details").array().filter { $0 !== details }
                for file in files {
                    let title = try protected.restore(file.children().first()?.text() ?? "")
                    let path = title.range(of: #" \([0-9]+\)$"#, options: .regularExpression).map { range in
                        String(title[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                    }
                    if let path, path.range(of: #"^\S+$|[/.]"#, options: .regularExpression) == nil {
                        continue
                    }

                    let anchored = try anchoredFindings(content(file), protected: protected, path: path)
                    if anchored.isEmpty == false {
                        findings += anchored
                        try file.remove()
                    }
                }
                try findings += anchoredFindings(content(details), protected: protected, path: nil)
            }
        }
        return findings
    }

    private static func content(_ details: Element) throws -> String {
        if let quote = details.children().first(where: { $0.tagName() == "blockquote" }) {
            return try quote.html()
        }
        return try details.getChildNodes()
            .filter { ($0 as? Element)?.tagName() != "summary" }
            .map { try $0.outerHtml() }
            .joined()
    }

    private static func anchoredFindings(_ source: String, protected: MarkdownHTMLCode, path: String?) -> [Finding] {
        var findings = [Finding]()
        for rawLine in source.components(separatedBy: "\n") {
            let text = protected.restore(rawLine).trimmingCharacters(in: .whitespaces)
            var anchor: (String, Int)?
            if let path, let match = text.firstMatch(of: /^`([0-9]+)(?:-[0-9]+)?`:/), let line = Int(match.1) {
                anchor = (path, line)
            } else if path == nil,
                      let match = text.firstMatch(of: /^\*\*([^*]+):([0-9]+)(?:-[0-9]+)?\*\*:/), let line = Int(match.2)
            {
                anchor = (String(match.1), line)
            } else if path == nil,
                      let match = text.wholeMatch(of: /^`([^`]+):([0-9]+)(?:-[0-9]+)?`$/), let line = Int(match.2)
            {
                anchor = (String(match.1), line)
            }
            if let (path, line) = anchor, path.isEmpty == false, line > 0 {
                findings.append(Finding(path: path, line: line, body: text))
            } else if findings.isEmpty == false {
                findings[findings.count - 1].body += "\n" + protected.restore(rawLine)
            }
        }
        return findings
    }

    private static func calloutDisclosures(_ source: String) -> String {
        Document(parsing: source)
            .children
            .compactMap { node -> String? in
                guard let quote = node as? BlockQuote, quote.children.contains(where: { child in
                    guard let paragraph = child as? Paragraph else {
                        return false
                    }

                    return paragraph.plainText.range(of: outsideDiffPattern, options: .regularExpression) != nil
                        && paragraph.plainText.range(of: #"\([1-9][0-9]*\)$"#, options: .regularExpression) != nil
                }) else {
                    return nil
                }

                return "<details><summary>Outside diff</summary>\n"
                    + quote.children.lazy.map { $0.detachedFromParent.format() }.joined(separator: "\n\n")
                    + "\n</details>"
            }
            .joined(separator: "\n")
    }

    private static func sourceLocation(_ node: any Markup) -> (path: String, line: Int)? {
        if let link = node as? Markdown.Link,
           link.plainText.range(of: sourceLinkPattern, options: .regularExpression) != nil,
           let destination = link.destination, let url = URL(string: destination), url.host == "github.com",
           let fragment = url.fragment, let match = fragment.wholeMatch(of: /L([0-9]+)(?:-L[0-9]+)?/),
           let line = Int(match.1), line > 0
        {
            let parts = url.pathComponents
            if parts.count > sourcePathStart, parts[blobComponent] == "blob" {
                return (parts.dropFirst(sourcePathStart).joined(separator: "/"), line)
            }
        }
        return node.children.lazy.compactMap { sourceLocation($0) }.first
    }
}
