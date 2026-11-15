import Foundation

// MARK: - SSHConfiguration

/// The saved destination; private keys are stored separately in Keychain.
public struct SSHConfiguration: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init() {
        // Preferences supply the initial values.
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        session = try container.decode(String.self, forKey: .session)
        awayHost = try container.decodeIfPresent(String.self, forKey: .awayHost) ?? ""
        awayPort = try container.decodeIfPresent(Int.self, forKey: .awayPort) ?? Self.defaultPort
        route = try container.decodeIfPresent(Route.self, forKey: .route) ?? .automatic
    }

    // MARK: Public

    public enum Route: String, Codable, CaseIterable, Sendable {
        case automatic = "Automatic"
        case home = "Home"
        case away = "Away"
    }

    public static let usernamePrefix = "sandvault-"

    public var host = ""
    public var port: Int = Self.defaultPort
    public var awayHost = ""
    public var awayPort: Int = Self.defaultPort
    public var route: Route = .automatic
    public var username: String = Self.usernamePrefix
    public var session = "sanductor"

    public var isValid: Bool {
        connectionCandidates.allSatisfy { endpoint in
            endpoint.endpointHost.isEmpty == false && (1 ... Self.maximumPort).contains(endpoint.port)
        }
            && username.hasPrefix(Self.usernamePrefix) && username.count > Self.usernamePrefix.count
            && username.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
            && session.isEmpty == false && session != "default"
            && session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Concrete endpoints share credentials but retain independent host-key pins.
    public var connectionCandidates: [Self] {
        var home = self
        home.awayHost = ""
        home.route = .home
        var away = home
        away.host = awayHost
        away.port = awayPort
        switch route {
        case .home:
            return [home]

        case .away:
            return [away]

        case .automatic:
            return away.endpointHost.isEmpty || home.hostIdentity == away.hostIdentity ? [home] : [home, away]
        }
    }

    public var hostIdentity: String {
        endpointHost.lowercased() + ":" + String(port)
    }

    /// The destination shared by connections, host-key pins and diagnostics.
    public var endpointHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func command(_ arguments: [String]) -> String {
        "unset HERDR_SOCKET_PATH; export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; "
            + "export HERDR_SESSION="
            + Self.quote(session) + "; exec " + arguments.map(Self.quote).joined(separator: " ")
    }

    // MARK: Internal

    static func quote(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }

    // MARK: Private

    private static let defaultPort = 22
    private static let maximumPort = 65_535
}

// MARK: - RemoteError

/// A remote command failed before its result could be used.
public struct RemoteError: Error, LocalizedError, Sendable {
    // MARK: Lifecycle

    public init(_ message: String) {
        self.message = message
    }

    // MARK: Public

    public var errorDescription: String? {
        message
    }

    // MARK: Private

    private let message: String
}
