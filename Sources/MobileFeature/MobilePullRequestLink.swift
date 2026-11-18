#if os(iOS)
    import SanductorDomain
    import SanductorInterface
    import SwiftUI
    import UIKit

    /// Universal links leave authentication and private repository access to GitHub.
    struct MobilePullRequestLink: View {
        // MARK: Internal

        let pullRequest: SidebarPullRequest

        var body: some View {
            if let url = pullRequest.webURL {
                Link(destination: url) {
                    HStack(spacing: Self.badgeSpacing) {
                        if let details = pullRequest.details {
                            Octicon(
                                ChecksStyle.stateOcticonName(
                                    state: details.state, isDraft: details.isDraft, isQueued: details.isQueued,
                                ),
                                colour: ChecksStyle.stateColour(
                                    state: details.state, isDraft: details.isDraft, isQueued: details.isQueued,
                                ),
                            )
                            Text("#" + String(pullRequest.number))
                                .accessibilityLabel("Pull request #" + String(pullRequest.number)
                                    + ", " + details.stateLabel)
                            if details.checks.isEmpty == false {
                                Octicon(ChecksStyle.checksOcticonName, colour: ChecksStyle.colour(for: details.checks))
                                    .accessibilityHidden(false)
                                    .accessibilityLabel("Checks: " + details.checksDescription)
                            }
                            conflictBadge
                            if let icon = ChecksStyle.reviewOcticonName(for: details.reviewDecision) {
                                Octicon(icon, colour: ChecksStyle.reviewColour(for: details.reviewDecision))
                                    .accessibilityHidden(false)
                                    .accessibilityLabel(ChecksStyle.reviewHelp(for: details.reviewDecision))
                            }
                        } else {
                            Label("#" + String(pullRequest.number), systemImage: "arrow.up.right")
                        }
                    }
                }
                .interfaceFont(.caption)
                .frame(minWidth: Self.minimumTouchSize)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .help("Open the Mac’s last reported PR in GitHub")
                .accessibilityHint("Open in GitHub. Status last reported by your Mac.")
                .environment(\.openURL, OpenURLAction { _ in
                    Task {
                        await pullRequest.open { url, universalLinksOnly in
                            await UIApplication.shared.open(url, options: [.universalLinksOnly: universalLinksOnly])
                        }
                    }
                    return .handled
                })
            }
        }

        // MARK: Private

        private static let minimumTouchSize: CGFloat = 44
        private static let badgeSpacing: CGFloat = 2

        @ViewBuilder private var conflictBadge: some View {
            if let mergeable = pullRequest.details?.mergeable,
               let icon = ChecksStyle.mergeableOcticonName(for: mergeable)
            {
                Octicon(icon, colour: ChecksStyle.mergeableColour(for: mergeable))
                    .accessibilityHidden(false)
                    .accessibilityLabel(ChecksStyle.mergeableHelp(for: mergeable))
                    .help(ChecksStyle.mergeableHelp(for: mergeable))
            }
        }
    }
#endif
