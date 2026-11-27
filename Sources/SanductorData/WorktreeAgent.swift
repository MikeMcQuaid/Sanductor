import Foundation
import SanductorDomain

/// The agent that last worked in this checkout, including from another repository's session.
public struct WorktreeAgent: Sendable {
    // MARK: Lifecycle

    /// Reads the worktree's own Git marker without following symlinks or opening its contents.
    public init?(at worktreePath: String) {
        var bytes = [UInt8](repeating: 0, count: Self.maximumLength)
        let count = unsafe getxattr(worktreePath + "/.git", Self.attribute, &bytes, bytes.count, 0, XATTR_NOFOLLOW)
        guard count > 0, let value = String(bytes: bytes.prefix(count), encoding: .utf8),
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._ =".contains($0)) })
        else {
            return nil
        }

        let parts = value.split(separator: " ", maxSplits: 1)
        guard let name = parts.first, let kind = AgentKind(rawValue: String(name)) else {
            return nil
        }

        agent = kind
        arguments = parts.dropFirst().first.map(String.init) ?? ""
    }

    // MARK: Public

    public let agent: AgentKind
    public let arguments: String

    // MARK: Private

    private static let maximumLength = 256
    private static let attribute = "com.mikemcquaid.Sanductor.agent"
}
