import Foundation
import Observation
import SanductorDomain

/// Account readings survive tab switches, with one request per agent per interval.
@preconcurrency
@Observable
@MainActor
public final class AgentQuotaModel {
    // MARK: Lifecycle

    /// Wires the sandbox reader without coupling the display to credentials or providers.
    @preconcurrency
    public init(read: @escaping @Sendable (AgentKind) async throws -> [AgentQuota]) {
        self.read = read
    }

    deinit {
        // The visible pane owns the polling task.
    }

    // MARK: Public

    /// The last good answer and whether the latest attempt failed.
    public struct Reading: Equatable {
        // MARK: Public

        /// Allowances reported by the account, never inferred from missing data.
        public var quotas: [AgentQuota] = []
        /// When the last successful request completed.
        public var updatedAt: Date?
        /// A failed request leaves earlier allowances visible but marked stale.
        public var isUnavailable = false

        // MARK: Internal

        /// Providers can give a shared reset slightly different fractional seconds.
        var quotaGroups: [[AgentQuota]] {
            var groups = [[AgentQuota]]()
            for quota in quotas {
                if let reset = quota.resetsAt,
                   let index = groups.firstIndex(where: { group in
                       group.first?.label == quota.label
                           && group.first?.resetsAt?.timeIntervalSince1970.rounded(.down)
                           == reset.timeIntervalSince1970.rounded(.down)
                   })
                {
                    groups[index].append(quota)
                } else {
                    groups.append([quota])
                }
            }
            return groups
        }
    }

    /// Missing entries are still awaiting their first reading.
    public private(set) var readings: [AgentKind: Reading] = [:]

    /// Called only while the Messages pane is visible; cancellation stops future reads.
    public func poll() async {
        while Task.isCancelled == false {
            await refresh()
            let remaining = RefreshCadence.agentQuotaSeconds - Date().timeIntervalSince(attemptedAt ?? .now)
            try? await Task.sleep(for: .seconds(max(1, remaining)))
        }
    }

    // MARK: Internal

    /// Throttles failures too, so revisiting the tab cannot hammer a rate-limited endpoint.
    func refresh(now: Date = .now) async {
        guard isRefreshing == false else {
            return
        }

        if let attemptedAt {
            let age = now.timeIntervalSince(attemptedAt)
            guard age < 0 || age >= RefreshCadence.agentQuotaSeconds else {
                return
            }
        }
        attemptedAt = now
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (AgentKind, [AgentQuota]?).self) { group in
            for agent in AgentKind.allCases {
                group.addTask { [read] in await (agent, try? read(agent)) }
            }
            for await (agent, quotas) in group {
                var reading = readings[agent] ?? Reading()
                if let quotas {
                    reading = Reading(quotas: quotas, updatedAt: now)
                } else {
                    reading.isUnavailable = true
                }
                if readings[agent] != reading {
                    readings[agent] = reading
                }
            }
        }
    }

    // MARK: Private

    @ObservationIgnored private var attemptedAt: Date?
    @ObservationIgnored private var isRefreshing = false
    private let read: @Sendable (AgentKind) async throws -> [AgentQuota]
}
