import SanductorDomain
import SwiftUI

/// Compact account and model allowances in the Messages footer.
public struct AgentQuotaView: View {
    // MARK: Lifecycle

    /// Uses the app's shared readings and refreshes only while visible.
    public init(model: AgentQuotaModel, isVisible: Bool) {
        self.model = model
        self.isVisible = isVisible
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach([AgentKind.codexCLI, .claudeCode], id: \.self) { agent in
                usage(agent, reading: model.readings[agent])
            }
        }
        .interfaceFont(.caption)
        .padding(Self.spacing)
        .task(id: isVisible) {
            if isVisible {
                await model.poll()
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let iconSize: CGFloat = 14

    private let model: AgentQuotaModel
    private let isVisible: Bool

    private func usage(_ agent: AgentKind, reading: AgentQuotaModel.Reading?) -> some View {
        HStack {
            AgentIcon(agent, size: Self.iconSize, coloured: true)
                .accessibilityHidden(true)
            Text(agent.displayName + " usage")
                .fixedSize()
            Spacer()
            if let reading {
                let groups = reading.quotaGroups
                if groups.isEmpty {
                    Text(reading.isUnavailable ? "Unavailable" : "Not reported")
                        .foregroundStyle(.secondary)
                        .hoverHelp("Check the agent's sign-in; quota reads retry automatically")
                } else {
                    VStack(alignment: .trailing) {
                        ForEach(groups, id: \.first?.id) { quotas in
                            allowance(quotas, reading: reading, showsPeriod: groups.count > 1)
                        }
                    }
                }
            } else {
                LaunchProgressView(spinner: "Reading quota")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func allowance(_ quotas: [AgentQuota], reading: AgentQuotaModel.Reading, showsPeriod: Bool) -> some View {
        let summary = HStack(alignment: .firstTextBaseline) {
            if showsPeriod {
                Text(quotas.first?.label ?? "").foregroundStyle(.secondary)
            }
            ForEach(quotas) { quota in
                if quota.id != quotas.first?.id {
                    Text("·").foregroundStyle(.secondary)
                }
                Text((quota.modelName.map { $0 + " " } ?? "")
                    + quota.usedPercent.formatted(.number.precision(.fractionLength(0 ... 1))) + "% used")
                    .monospacedDigit()
            }
            if reading.isUnavailable {
                Text("Stale").foregroundStyle(.secondary)
            }
        }
        let resetTime = Group {
            if let reset = quotas.first?.resetsAt {
                Text("Resets " + reset.formatted(.dateTime.weekday().hour().minute()))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .hoverHelp(reset.formatted(date: .complete, time: .shortened))
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                summary
                resetTime
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing) {
                summary
                resetTime
            }
        }
        .hoverHelp((quotas.first?.label ?? "") + " allowance. Updated "
            + (reading.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")
            + ". Refreshes every 10 minutes while Messages is visible.")
    }
}
