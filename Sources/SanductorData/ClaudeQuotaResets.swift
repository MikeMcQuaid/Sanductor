import Foundation

// MARK: - ClaudeQuotaResetResponse

/// Decoded separately so unsupported reset metadata cannot hide ordinary usage.
struct ClaudeQuotaResetResponse: Decodable {
    let cedarEmber: ClaudeQuotaResets?
}

// MARK: - ClaudeQuotaResets

/// Optional reset grants from Claude's usage endpoint, scoped to the limits they clear.
struct ClaudeQuotaResets: Decodable {
    struct Grant: Decodable {
        let id: String
        let resetsLeft: Int
        let clears: [String]
        let startsAt: String?
        let endsAt: String?
        // swiftlint:disable:next discouraged_optional_boolean - Older responses omit this flag.
        let paused: Bool?
    }

    let eligible: Bool
    // swiftlint:disable:next discouraged_optional_collection - Missing grants are unknown, not zero.
    let grants: [Grant]?

    func available(for window: String?, now: Date) -> Int? {
        guard eligible, let grants, let window else {
            return nil
        }

        var seen = Set<String>()
        var total = 0
        for grant in grants where grant.clears.contains(window) && grant.paused != true {
            guard grant.resetsLeft >= 0, seen.insert(grant.id).inserted else {
                continue
            }

            if let start = grant.startsAt {
                guard let date = (try? Date(start, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                    ?? (try? Date(start, strategy: .iso8601))
                else {
                    return nil
                }

                if date > now {
                    continue
                }
            }
            if let end = grant.endsAt {
                guard let date = (try? Date(end, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                    ?? (try? Date(end, strategy: .iso8601))
                else {
                    return nil
                }

                if date <= now {
                    continue
                }
            }
            let sum = total.addingReportingOverflow(grant.resetsLeft)
            guard sum.overflow == false else {
                return nil
            }

            total = sum.partialValue
        }
        return total
    }
}
