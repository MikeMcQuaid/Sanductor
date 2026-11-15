import Foundation
import SanductorDomain

public extension SessionService {
    /// Reads only quota data across the sandbox boundary, with bounded output and request time.
    func quota(for agent: AgentKind) async throws -> [AgentQuota] {
        let adapter = runner(for: agent)
        guard let payload = adapter.quotaCommand else {
            return []
        }

        let result = try await processes.run(
            launcher.command(
                payload: Self.quotaPayload(payload),
                initialDirectory: paths.sandboxHome,
                sessionID: UUID().uuidString,
                sessionName: "sanductor-quota-" + agent.rawValue,
            ),
            workingDirectory: nil,
            environment: [:],
            outputLimit: Self.quotaOutputLimit,
        )
        guard result.succeeded else {
            // Provider responses and credential helpers must never reach the message log.
            throw SessionServiceError("Quota unavailable. Check the agent's sign-in or try again later.")
        }

        return try adapter.parseQuota(Data(result.standardOutput.utf8))
    }

    /// Kill inside the sandbox: the host cannot signal another user's credential helpers.
    internal static func quotaPayload(_ payload: String, timeoutSeconds: Int = 30) -> String {
        // Braced variables survive sudo's login-shell escaping without expansion.
        "exec /usr/bin/perl -e " + """
        my ${seconds} = shift @ARGV; \
        setpgrp(0, 0) or die "quota process group"; \
        ${SIG{TERM}} = ${SIG{ALRM}} = sub { kill 9, -${$}; }; \
        alarm ${seconds}; \
        my ${child} = fork(); \
        defined ${child} or die "quota fork"; \
        if (${child} == 0) { exec @ARGV; exit 127; } \
        waitpid(${child}, 0); \
        my ${status} = ${?}; \
        alarm 0; \
        exit((${status} & 127) ? 128 + (${status} & 127) : ${status} >> 8);
        """.shellQuoted + " " + String(timeoutSeconds)
            + " /bin/zsh -fc " + payload.shellQuoted
    }

    private static let quotaOutputLimit = 1_048_576
}
