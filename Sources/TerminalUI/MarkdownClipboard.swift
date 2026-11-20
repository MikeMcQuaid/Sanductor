import AppKit
import Markdown

/// Copies a reply the way a browser copies a page: as formatted text
/// for whatever takes it (Word, Slack, Mail), beside the Markdown
/// itself for everything that takes plain text.
public enum MarkdownClipboard {
    // MARK: Public

    /// Replaces the pasteboard's contents with the reply.
    public static func copy(_ markdown: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        var legible = Legible()
        let document = legible.visit(Document(parsing: markdown)) ?? Document()
        // Named as UTF-8, or a receiver may read the fragment as Latin-1.
        pasteboard.setString("<meta charset=\"utf-8\">" + HTMLFormatter.format(document), forType: .html)
        pasteboard.setString(markdown, forType: .string)
    }

    /// Copies a reply that takes a moment to read, unless something
    /// else was copied meanwhile: the newer copy is the one meant.
    public static func copy(to pasteboard: NSPasteboard = .general, reading reply: () async -> String?) async {
        let changes = pasteboard.changeCount
        if let markdown = await reply(), pasteboard.changeCount == changes {
            copy(markdown, to: pasteboard)
        }
    }

    // MARK: Private

    /// Readies a reply's tree for swift-markdown's formatter, which
    /// writes text and code out as they stand. Unescaped, a `<name>`
    /// in either read as a tag and vanished, and a bare `<code>` means
    /// nothing to a receiver that keeps fonts rather than tags, where
    /// file names landed in the body's face. So code names its own
    /// font and everything written is escaped, the agent's raw HTML
    /// included, which pastes as the text it is, and a link's or an
    /// image's attributes, which could otherwise close their quotes.
    private nonisolated struct Legible: MarkupRewriter {
        // MARK: Internal

        func visitText(_ text: Text) -> (any Markup)? {
            Text(Self.escaped(text.string))
        }

        func visitInlineCode(_ inlineCode: InlineCode) -> (any Markup)? {
            InlineHTML("<code style=\"" + Self.codeStyle + "\">" + Self.escaped(inlineCode.code) + "</code>")
        }

        func visitCodeBlock(_ codeBlock: CodeBlock) -> (any Markup)? {
            HTMLBlock(
                "<pre style=\"" + Self.codeStyle + "\"><code>" + Self.escaped(codeBlock.code) + "</code></pre>\n",
            )
        }

        func visitInlineHTML(_ inlineHTML: InlineHTML) -> (any Markup)? {
            Text(Self.escaped(inlineHTML.rawHTML))
        }

        func visitHTMLBlock(_ html: HTMLBlock) -> (any Markup)? {
            HTMLBlock("<p>" + Self.escaped(html.rawHTML) + "</p>\n")
        }

        mutating func visitLink(_ link: Link) -> (any Markup)? {
            guard var rewritten = defaultVisit(link) as? Link else {
                return nil
            }

            rewritten.destination = rewritten.destination.map(Self.escaped)
            return rewritten
        }

        func visitImage(_ image: Image) -> (any Markup)? {
            var image = image
            image.source = image.source.map(Self.escaped)
            image.title = image.title.map(Self.escaped)
            return image
        }

        // MARK: Private

        private static let codeStyle = "font-family: Menlo, Monaco, 'Courier New', monospace"

        private static func escaped(_ text: String) -> String {
            text.replacing("&", with: "&amp;")
                .replacing("<", with: "&lt;")
                .replacing(">", with: "&gt;")
                .replacing("\"", with: "&quot;")
        }
    }
}
