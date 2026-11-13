import Foundation
import SwiftUI

public extension EnvironmentValues {
    /// The repository whose issue numbers appear in Markdown prose.
    @Entry var markdownRepositoryURL: URL?
}

extension MarkdownText {
    static func linkingIssues(_ original: AttributedString, repositoryURL: URL?) -> AttributedString {
        guard let repositoryURL, let issueReference else {
            return original
        }

        var content = original
        for (intent, block) in original.runs[\.presentationIntent] {
            guard intent?.components.contains(where: { component in
                if case .codeBlock = component.kind {
                    return true
                }
                return false
            }) != true else {
                continue
            }

            let text = String(original[block].characters)
            for match in issueReference.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else {
                    continue
                }

                let lower = original.characters.index(
                    block.lowerBound, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound),
                )
                let upper = original.characters.index(lower, offsetBy: text[range].count)
                guard original[lower ..< upper].runs.allSatisfy({ run in
                    run.link == nil && run.imageURL == nil && run.inlinePresentationIntent?.contains(.code) != true
                }) else {
                    continue
                }

                content[lower ..< upper].link = repositoryURL.appending(path: "issues/" + text[range].dropFirst())
            }
        }
        return content
    }

    private static let issueReference = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/#])#[1-9][0-9]*(?![\p{L}\p{N}_])"#,
    )
}
