import Foundation
import SanductorDomain

public extension AgentRunner {
    /// Adapters without a quota interface leave it unavailable.
    var quotaCommand: String? {
        nil
    }

    /// Secrets go through curl's standard input, never process arguments or files.
    internal func quotaRequest(url: String, headers: String = "") -> String {
        #"[[ "${quota_token}" =~ '^[A-Za-z0-9._~+/=-]+$' ]] || exit 1; "#
            + #"{ printf 'header = "Authorization: Bearer %s"\n' "${quota_token}"; "#
            + headers + " } | /usr/bin/curl -q --silent --fail --connect-timeout 10 --max-time 20"
            + " --max-filesize 1048576 --proto '=https' --config - " + url.shellQuoted
    }
}

public extension ClaudeCodeRunner {
    /// Uses the same OAuth usage endpoint as Claude Code's /usage command.
    var quotaCommand: String? {
        """
        unsetopt xtrace; quota_token=''; \
        for quota_keychain in "${HOME}/Library/Keychains/sandvault.keychain-db" \
          "${HOME}/Library/Keychains/login.keychain-db"; do \
          [[ -f "${quota_keychain}" ]] || continue; \
          /usr/bin/security unlock-keychain -p '' "${quota_keychain}" &>/dev/null || continue; \
          quota_token=$(/usr/bin/security find-generic-password -a "${USER}" \
            -s 'Claude Code-credentials' -w "${quota_keychain}" 2>/dev/null \
            | /usr/bin/plutil -extract claudeAiOauth.accessToken raw -o - - 2>/dev/null) || quota_token=''; \
          [[ -n "${quota_token}" ]] && break; \
        done; \
        if [[ -z "${quota_token}" ]]; then \
          quota_token=$(/usr/bin/plutil -extract claudeAiOauth.accessToken raw -o - \
            "${HOME}/.claude/.credentials.json" 2>/dev/null) || exit 1; \
        fi;
        """ + quotaRequest(
            url: "https://api.anthropic.com/api/oauth/usage",
            headers: #"printf 'header = "anthropic-beta: oauth-2025-04-20"\n';"#,
        )
    }

    /// Structured limits supply model names, including Fable's separate weekly allowance.
    func parseQuota(_ data: Data) throws -> [AgentQuota] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ClaudeQuotaResponse.self, from: data)
        if let limits = response.limits, limits.isEmpty == false {
            return limits.compactMap { limit in
                guard let percent = limit.percent, percent.isFinite, percent >= 0 else {
                    return nil
                }

                let period: String
                switch limit.group {
                case "weekly":
                    period = "Weekly"

                case "five_hour",
                     "session":
                    period = "5 hours"

                default:
                    return nil
                }
                let name = limit.scope?.model?.displayName.map { String($0.prefix(Self.quotaNameLimit)) }
                return AgentQuota(
                    id: limit.kind + "/" + (name ?? ""),
                    label: period,
                    usedPercent: percent,
                    resetsAt: limit.resetsAt.flatMap(Self.quotaReset),
                    modelName: name,
                )
            }
        }
        return [
            ("five_hour", "5 hours", nil as String?, response.fiveHour),
            ("seven_day", "Weekly", nil, response.sevenDay),
            ("seven_day_overage_included", "Weekly", "Fable", response.sevenDayOverageIncluded),
            ("seven_day_opus", "Weekly", "Opus", response.sevenDayOpus),
            ("seven_day_sonnet", "Weekly", "Sonnet", response.sevenDaySonnet),
        ].compactMap { id, label, name, window in
            guard let window, window.utilization.isFinite, window.utilization >= 0 else {
                return nil
            }

            return AgentQuota(
                id: id,
                label: label,
                usedPercent: window.utilization,
                resetsAt: window.resetsAt.flatMap(Self.quotaReset),
                modelName: name,
            )
        }
    }

    private static let quotaNameLimit = 80

    private static func quotaReset(_ value: String) -> Date? {
        (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}

// MARK: - ClaudeQuotaResponse

private struct ClaudeQuotaResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double
        let resetsAt: String?
    }

    // Missing on older clients' responses; default decoding must accept absent keys.
    // swiftlint:disable:next discouraged_optional_collection
    let limits: [ClaudeQuotaLimit]?
    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDayOverageIncluded: Window?
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?
}

// MARK: - ClaudeQuotaLimit

private struct ClaudeQuotaLimit: Decodable {
    let kind: String
    let group: String
    let percent: Double?
    let resetsAt: String?
    let scope: ClaudeQuotaScope?
}

// MARK: - ClaudeQuotaScope

private struct ClaudeQuotaScope: Decodable {
    struct Model: Decodable {
        let displayName: String?
    }

    let model: Model?
}
