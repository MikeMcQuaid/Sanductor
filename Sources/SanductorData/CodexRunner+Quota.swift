import Foundation
import SanductorDomain

public extension CodexRunner {
    /// Uses Codex's account usage endpoint with the sandbox account's stored sign-in.
    var quotaCommand: String? {
        """
        unsetopt xtrace; \
        quota_token=$(/usr/bin/plutil -extract tokens.access_token raw -o - \
          "${HOME}/.codex/auth.json" 2>/dev/null) || exit 1; \
        quota_account=$(/usr/bin/plutil -extract tokens.account_id raw -o - \
          "${HOME}/.codex/auth.json" 2>/dev/null) || exit 1; \
        [[ "${quota_account}" =~ '^[A-Za-z0-9_-]+$' ]] || exit 1;
        """ + quotaRequest(
            url: "https://chatgpt.com/backend-api/wham/usage",
            headers: #"printf 'header = "ChatGPT-Account-Id: %s"\n' "${quota_account}";"#,
        )
    }

    /// Window durations, rather than their ordering, determine the labels.
    func parseQuota(_ data: Data) throws -> [AgentQuota] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(CodexQuotaResponse.self, from: data)
        return [
            ("primary", response.rateLimit?.primaryWindow),
            ("secondary", response.rateLimit?.secondaryWindow),
        ].compactMap { id, window in
            guard let window, window.usedPercent.isFinite, window.usedPercent >= 0 else {
                return nil
            }

            let label =
                switch window.limitWindowSeconds {
                case Self.fiveHours:
                    "5 hours"

                case Self.oneWeek:
                    "Weekly"

                default:
                    "Account limit"
                }
            return AgentQuota(
                id: id,
                label: label,
                usedPercent: window.usedPercent,
                resetsAt: window.resetAt.map(Date.init(timeIntervalSince1970:)),
            )
        }
    }

    private static let fiveHours = 18_000
    private static let oneWeek = 604_800
}

// MARK: - CodexQuotaResponse

private struct CodexQuotaResponse: Decodable {
    struct RateLimit: Decodable {
        let primaryWindow: CodexQuotaWindow?
        let secondaryWindow: CodexQuotaWindow?
    }

    let rateLimit: RateLimit?
}

// MARK: - CodexQuotaWindow

private struct CodexQuotaWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAt: TimeInterval?
}
