import Foundation

/// A file a command outside the app is waiting to have edited: one
/// request from the `sanductor` editor shim, which host shells point
/// `EDITOR`, `VISUAL` and `GIT_EDITOR` at.
public struct ExternalEdit: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a request.
    public init(
        id: String,
        path: String,
        workingDirectory: String,
        processIdentifier: Int32,
        kind: Kind = .edit,
        session: Session? = nil,
    ) {
        self.id = id
        self.path = path
        self.workingDirectory = workingDirectory
        self.processIdentifier = processIdentifier
        self.kind = kind
        self.session = session
    }

    /// Decodes one spooled request, whose file name is its id; nil
    /// when the file is not a request this version understands.
    public init?(id: String, json: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: json) else {
            return nil
        }

        let asked = payload.kind.flatMap(Kind.init(rawValue:)) ?? .edit
        // A session request says what to start, and nothing else does.
        guard (asked == .session) == (payload.session != nil) else {
            return nil
        }

        self.init(
            id: id,
            path: payload.path,
            workingDirectory: payload.workingDirectory,
            processIdentifier: payload.processIdentifier,
            kind: asked,
            session: payload.session,
        )
    }

    // MARK: Public

    // The formatter strips raw values equal to their case name and
    // the linter asks for them, so the rule is off here, as it is
    // around coding keys.
    // swiftlint:disable explicit_enum_raw_value

    /// What the command asked the app for.
    public enum Kind: String, Sendable {
        /// Edit this file and hold the command until it is done.
        case edit

        /// Show this file; the command has already gone.
        case open

        /// Select this worktree or repository.
        case select

        /// Start a session in this repository from a GitHub source
        /// and hold the command until it has started or failed.
        case session
    }

    /// Where a session request's prompt comes from.
    public enum Source: String, Decodable, Sendable {
        /// An issue, by number.
        case issue

        /// An open pull request, by number, worked on in its own
        /// branch.
        case pullRequest = "pull-request"

        /// A discussion, by address: it may belong to the
        /// organisation rather than the repository.
        case discussion
    }

    /// What `sanductor new` asks the app to start when the prompt is
    /// GitHub's to supply: only the app may ask GitHub or check a
    /// pull request out, so the command hands over its arguments as
    /// it took them.
    public struct Session: Decodable, Hashable, Sendable {
        /// The agent's name as session names spell it.
        public let agent: String

        /// The model, empty for the agent's own default.
        public let model: String

        /// The effort, empty for the model's own default.
        public let effort: String

        /// Where the prompt comes from.
        public let source: Source

        /// Which one: a number, or a discussion's address.
        public let reference: String

        /// What the user added, which may be nothing.
        public let context: String
    }

    // swiftlint:enable explicit_enum_raw_value

    /// What was asked for.
    public let kind: Kind

    /// What to start, for a session request and no other.
    public let session: Session?

    /// The request's identity, which is its spool file's name.
    public let id: String

    /// The absolute path of the file to edit. It is regularly
    /// outside every worktree: a linked worktree's rebase todo list
    /// lives in the repository's own `.git` directory.
    public let path: String

    /// The directory the command ran in, which locates the worktree
    /// whose pane shows the file.
    public let workingDirectory: String

    /// The shim's process, so a request whose command has gone can
    /// be swept: the shim always waits, so its process being alive
    /// is exactly the request still mattering.
    public let processIdentifier: Int32

    /// Whether the command is still there waiting for an answer;
    /// only then does its process being alive mean anything.
    public var waitsForAnswer: Bool {
        kind == .edit || kind == .session
    }

    /// The file's name, for the editor's header.
    public var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Whether the command ran inside a worktree, so that the
    /// worktree's editor pane is the one that should show the file.
    public func belongs(toWorktree worktreePath: String) -> Bool {
        workingDirectory == worktreePath || workingDirectory.hasPrefix(worktreePath + "/")
    }

    // MARK: Private

    /// The shim writes exactly these fields.
    private struct Payload: Decodable {
        let path: String
        let workingDirectory: String
        let processIdentifier: Int32
        /// Absent in requests from an older shim, which all waited.
        let kind: String?
        let session: Session?
    }
}
