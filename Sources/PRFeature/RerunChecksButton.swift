import SanductorDomain
import SwiftUI
import TerminalUI

struct RerunChecksButton: View {
    // MARK: Internal

    let model: PullRequestsModel
    let summary: PullRequestSummary
    var check: PullRequestCheck?

    var body: some View {
        let count = check == nil ? (summary.checkDetails ?? []).count(where: \.canRerun) : 1
        BusyButton(
            "",
            busy: "",
            systemImage: "arrow.clockwise",
            accessibilityLabel: check.map { "Rerun " + $0.displayName }
                ?? "Rerun " + String(count) + " failed jobs",
            disabled: model.isRerunningChecks || count == 0,
        ) {
            if await model.rerunChecks(summary, check: check) == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .controlSize(.small)
        .hoverHelp(check.map { "Rerun " + $0.displayName + " and its dependent jobs" }
            ?? "Rerun all " + String(count) + " failed Actions jobs, "
            + "including optional and hidden checks, and their dependent jobs")
    }

    // MARK: Private

    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = ""
}
