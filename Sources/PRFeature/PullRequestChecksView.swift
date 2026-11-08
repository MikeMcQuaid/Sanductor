import SanductorDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestChecksView

/// All checks on the current head, with individual job logs on demand.
struct PullRequestChecksView: View {
    // MARK: Internal

    let model: PullRequestsModel
    let summary: PullRequestSummary
    let filter: PullRequestCheckFilter

    var body: some View {
        if let checks = summary.checkDetails {
            if let selected = checks.first(where: { $0.id == selectedID }) {
                CheckLogView(check: selected, fetchLog: model.fetchCheckLog, preparePrompt: model.preparePrompt) {
                    selectedID = nil
                }
                .id(selected.id)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        rerunButton()
                    }
                    .padding(Self.spacing)
                    Divider()
                    list(checks)
                }
            }
        } else {
            LaunchProgressView(spinner: "Loading CI checks…")
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private static let dotInset: CGFloat = 3
    private static let rowPadding: CGFloat = 4

    @State private var selectedID: String?
    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = ""

    private func list(_ checks: [PullRequestCheck]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(checks.filter(filter.includes)) { check in
                    HStack(spacing: Self.spacing) {
                        Button { selectedID = check.id } label: {
                            row(check).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverHelp("View the log for " + check.displayName)
                        if check.canRerun {
                            rerunButton(check)
                        }
                    }
                    .padding(.horizontal, Self.spacing)
                    .padding(.vertical, Self.rowPadding)
                    Divider()
                }
                if checks.contains(where: filter.includes) == false {
                    Text(checks.isEmpty ? "No CI checks." : "No matching checks.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private func rerunButton(_ check: PullRequestCheck? = nil) -> some View {
        let count = check == nil ? (summary.checkDetails ?? []).count(where: \.canRerun) : 1
        return BusyButton(
            check == nil ? "Rerun failed (" + String(count) + ")" : "",
            busy: check == nil ? "Requesting reruns" : "",
            systemImage: "arrow.clockwise",
            accessibilityLabel: check.map { "Rerun " + $0.displayName } ?? "Rerun failed jobs",
            disabled: model.isRerunningChecks || count == 0,
        ) {
            if await model.rerunChecks(summary, check: check) == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(check.map { "Rerun " + $0.displayName + " and its dependent jobs" }
            ?? "Rerun all failed Actions jobs, including optional and hidden checks, and their dependent jobs")
    }

    private func row(_ check: PullRequestCheck) -> some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            Octicon(ChecksStyle.checksOcticonName, colour: ChecksStyle.colour(for: check.conclusion))
                .padding(.top, Self.dotInset)
            VStack(alignment: .leading, spacing: Self.dotInset) {
                Text(check.displayName)
                    .interfaceFont(.callout, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                CheckStatusView(check: check)
            }
            Spacer(minLength: 0)
            Text("(" + check.requirement.rawValue + ")")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

// MARK: - CheckStatusView

struct CheckStatusView: View {
    let check: PullRequestCheck

    var body: some View {
        Group {
            if let duration = check.duration {
                Text(check.statusDescription + " in " + Duration.seconds(duration).formatted(
                    .units(allowed: [.hours, .minutes, .seconds], width: .narrow),
                ))
            } else if check.status == "IN_PROGRESS", let start = check.startedAt {
                Text("Running for \(Text(start, style: .timer))")
            } else if check.isComplete || check.status == "IN_PROGRESS" || check.status == "PENDING" {
                Text(check.statusDescription + " · Duration unavailable")
            } else {
                Text(check.statusDescription)
            }
        }
        .interfaceFont(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
