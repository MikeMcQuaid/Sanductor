/// Checkout paths due for a Git read. A repository path refreshes
/// all its rows, while a linked worktree path refreshes its own.
public enum GitReadScope: Sendable {
    case all
    case only(Set<String>)

    // MARK: Public

    /// Whether this checkout is explicitly due.
    public func includes(_ path: String) -> Bool {
        switch self {
        case .all:
            true

        case let .only(paths):
            paths.contains(path)
        }
    }
}
