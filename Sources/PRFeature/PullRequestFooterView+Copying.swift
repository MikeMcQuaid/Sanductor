import SanductorDomain
import SwiftUI
import TerminalUI

/// The footer's copy buttons: what a click takes to the
/// clipboard, said in a word and, when there is any of it, the
/// app's own copy symbol and a count, in the run the sidebar's
/// arrows use. Split from the footer for length.
extension PullRequestFooterView {
    /// The copy actions for the open conversation, in the footer's
    /// click-order run.
    @ViewBuilder
    func copyButtons(for selected: PullRequestSummary) -> some View {
        let count = reviewCount(for: selected)
        // The word says what, the glyph that a click copies it and
        // the count how much there is; none of it dims the button
        // to the word alone, which is the same fact the count
        // would have reported.
        BusyButton(
            label: copyLabel("Reviews", count: count),
            accessibilityLabel: Self.copyTitle("Reviews", count: count),
            busy: "Copying",
            disabled: count == 0,
        ) { modifiers in
            // Both buttons read the modifier at the click, as
            // `LinkOpener` does: Cmd goes to the browser, Shift to
            // the Browser tab, a plain click to the clipboard.
            if modifiers.isDisjoint(with: [.command, .shift]) == false {
                model.openReviews(selected, inExternalBrowser: modifiers.contains(.command))
            } else if modifiers.contains(.option) {
                await model.copyUnresolvedComments(selected, resolve: true)
            } else {
                await model.copyUnresolvedComments(selected)
            }
        }
        .hoverHelp("Copy unresolved local AI and GitHub conversations and outside-diff findings, "
            + "excluding those marked Resolve on push. "
            + "Cmd-click opens GitHub reviews in your browser, Shift-click in the Browser tab. "
            + "Option-click copies first, then marks all GitHub conversations Resolve on push "
            + "and resolves local and outside-diff findings")
        .contextMenu {
            BusyButton("Copy and resolve all reviews on push", busy: "Copying reviews", disabled: count == 0) {
                await model.copyUnresolvedComments(selected, resolve: true)
            }
        }
        let checks = PullRequestsModel.copyableFailingChecks(
            in: selected, includeOptional: model.includesOptionalLogs(for: selected),
        )
        BusyButton(
            label: copyLabel("Checks", count: checks.count),
            accessibilityLabel: Self.copyTitle("Checks", count: checks.count),
            busy: "Copying " + String(checks.count),
            disabled: checks.isEmpty,
        ) { modifiers in
            if modifiers.isDisjoint(with: [.command, .shift]) == false {
                model.openFailingChecks(selected, inExternalBrowser: modifiers.contains(.command))
            } else if await model.copyFailingLogs(selected) == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp("Copy logs from " + String(checks.count) + " finished failing Actions checks, "
            + "including diagnostics from long logs; unfinished checks are excluded, "
            + "Right-click to include optional checks for this PR. "
            + "Cmd-click opens failing checks in your browser, Shift-click in the Browser tab")
        .contextMenu {
            Toggle("Include Optional Checks", isOn: Binding(
                get: { model.includesOptionalLogs(for: selected) },
                set: { model.setIncludesOptionalLogs($0, for: selected) },
            ))
        }
    }

    /// Explicit manual copies retain their broader scope beside filtered feedback.
    func rawFeedbackMenu(for selected: PullRequestSummary) -> some View {
        Menu("Copy unfiltered feedback") {
            BusyButton("All unresolved reviews", busy: "Copying reviews") {
                await model.copyUnresolvedComments(selected)
            }
            .disabled(reviewCount(for: selected) == 0)
            Button("Failing CI logs") {
                Task {
                    if await model.copyFailingLogs(selected) == false {
                        utilityTab = UtilityTabTarget.errors
                    }
                }
            }
            .disabled(PullRequestsModel.copyableFailingChecks(
                in: selected, includeOptional: model.includesOptionalLogs(for: selected),
            )
            .isEmpty)
        }
    }

    /// The symbol every copy in the app carries, drawn inline at the
    /// text's own size between the word and the count, where
    /// `Push ↑9` puts its arrow: a character that looked like it did
    /// not look like it.
    static let copyIcon = "doc.on.doc"

    private func reviewCount(for summary: PullRequestSummary) -> Int {
        _ = reviewGeneration
        _ = resolutionGeneration
        return model.reviewCount(for: summary)
    }

    /// A copy button's label: what it copies and, when there is
    /// any, the symbol and the count. Nothing to copy is the word
    /// alone, greyed out.
    func copyLabel(_ name: String, count: Int) -> Text {
        guard count > 0 else {
            return Text(name)
        }

        let icon = Text(Image(systemName: Self.copyIcon)).font(interfaceStyle.systemFont(ofSize: Self.copyIconSize))
        return Text("\(name) \(icon)\(String(count))")
    }

    /// The symbol's size: the label's own is thirteen points, and
    /// a symbol drawn at that overhung the digits beside it; about
    /// a third smaller sits on the baseline with them.
    private static let copyIconSize: CGFloat = 9

    /// The same as VoiceOver reads it.
    static func copyTitle(_ name: String, count: Int) -> String {
        if count > 0 {
            name + " " + String(count)
        } else {
            name
        }
    }
}
