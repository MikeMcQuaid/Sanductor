import SanductorData
import SanductorDomain
import TerminalUI

/// Which branch the tab acts on and whether it can: an entry of a
/// stack is read without being checked out, so what a button reads
/// and what it moves are not always the branch the worktree holds.
/// Split from the actions for length.
extension PullRequestsModel {
    /// What the worktree itself says: its stack, signing, rebase
    /// need, template and checked-out branch. Skipped when moving
    /// between a stack's entries, which share all of it.
    func refreshWorktreeFacts(_ worktree: Worktree) async {
        // Claim the refresh before a slow stack read can be superseded.
        stacking.factsGeneration += 1
        let generation = stacking.factsGeneration
        await loadStack()
        guard generation == stacking.factsGeneration else {
            return
        }

        // Before the counts are read: a pull request from a fork has
        // no tracking ref until its remote is named, and everything
        // below counts against one.
        let live = await fetchCurrentBranch(worktree.path)
        let selection = stacking.selected
        let listed = self.worktree(on: selection ?? live ?? listedBranch) ?? worktree
        _ = await nameFork(listed)
        let tip = await fetchTipCommit(listed)
        let signature: TipSignature =
            if let tip {
                await checkSignature(listed, tip) ? .signed : .unsigned
            } else {
                .unread
            }
        let need = await fetchRebaseNeed(listed)
        let template = await fetchTemplate(worktree.path)
        let labels = availableLabels.isEmpty ? await fetchLabels() : availableLabels
        guard generation == stacking.factsGeneration, selection == stacking.selected else {
            return
        }

        if let live {
            currentBranch = live
        }
        tipSignature = signature
        // Only the tip moving unpushes a branch: new commits, an
        // amend or a rebase, all of which give the push something
        // to send again. A tip that could not be read has moved
        // nowhere, and clearing the mark on it would relight Push
        // exactly as the stale counts used to.
        if let mark = pushedTip, let tip, mark.branch == (listedBranch ?? worktree.branch), mark.commit != tip {
            pushedTip = nil
        }
        rebaseNeed = need
        availableLabels = labels
        hasTemplate = template != nil
        originalTemplate = template ?? ""
        if prTemplate.isEmpty {
            prTemplate = originalTemplate
        }
        await prefillFromSingleCommit(listed)
    }

    /// The rebase button's label names exactly what it would do.
    var rebaseTitle: String {
        guard AppSettings.requiresSignedCommits else {
            return "Rebase on origin"
        }

        return switch rebaseNeed {
        case .sign:
            "Sign commits"

        case .rebaseAndSign:
            "Rebase and sign"

        case .nothing,
             .rebase:
            "Rebase on origin"
        }
    }

    /// Rebase only lights up when it would actually change
    /// something: move the base, sign commits, or both. It acts on
    /// the entry in view, checking it out for the rebase and putting
    /// the worktree back: an entry whose tip is unsigned could
    /// otherwise never be pushed, since Push waits for the signature
    /// only this can give it.
    var canRebase: Bool {
        branchItem != nil && isBranchActionRunning == false && queuedBranchBlocker == nil
            && rebaseNeed != SessionService.RebaseNeed.nothing
    }

    func rebaseSigned() async -> Bool {
        // Rebasing one layer alone would detach the branches stacked above it.
        guard stacking.stack.isStacked == false else {
            return await restack()
        }
        guard let worktree = listedWorktree else {
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        // What it is about to do, before doing it moves the branch
        // and leaves nothing to read it from.
        let onlySigns = rebaseNeed == SessionService.RebaseNeed.sign
        do {
            var result = try await rebaseAndVerify(worktree)
            if result.signature == .unsigned {
                result = try await rebaseAndVerify(worktree)
            }
            if result.signature == .unread {
                UtilityTabTarget.requestSidebarRefresh()
                report("Could not confirm the current tip of `" + worktree.branch + "` after rebasing")
                return false
            }
            // Done means Push agrees; reporting success with the tip
            // still unsigned took a second press to notice.
            if result.signature == .unsigned {
                report("Rebased twice, but the tip still reads unsigned; check the signing key")
                return false
            }
            recordFinished(onlySigns ? .signed : .rebased, branch: worktree.branch)
            note("Rebased `" + worktree.branch + "` on `" + result.target + "` and signed it.")
            UtilityTabTarget.requestSidebarRefresh()
            return true
        } catch {
            if listedWorktree == worktree {
                stacking.factsGeneration += 1
                tipSignature = .unread
            }
            UtilityTabTarget.requestSidebarRefresh()
            report(error.localizedDescription)
            return false
        }
    }

    private func rebaseAndVerify(_ worktree: Worktree) async throws -> (target: String, signature: TipSignature) {
        let target = try await performRebase(worktree)
        let need = await fetchRebaseNeed(worktree)
        guard listedWorktree == worktree else {
            return (target, .unread)
        }

        stacking.factsGeneration += 1
        let verificationGeneration = stacking.factsGeneration
        tipSignature = .unread
        guard let commit = await fetchTipCommit(worktree) else {
            return (target, .unread)
        }

        var signed = await checkSignature(worktree, commit)
        if signed == false {
            try? await Task.sleep(for: .milliseconds(Self.signatureSettleMilliseconds))
            signed = await checkSignature(worktree, commit)
        }
        let confirmationGeneration = stacking.factsGeneration
        guard await fetchTipCommit(worktree) == commit, listedWorktree == worktree,
              confirmationGeneration == stacking.factsGeneration
        else {
            return (target, .unread)
        }

        let signature: TipSignature = signed ? .signed : .unsigned
        // A concurrent refresh owns the displayed facts even when it saw the same tip.
        if verificationGeneration == confirmationGeneration {
            rebaseNeed = need
            tipSignature = signature
        }
        return (target, signature)
    }

    /// How long a tip that reads unsigned straight after a rebase
    /// is given before it is read again.
    static let signatureSettleMilliseconds = 500

    /// The one merge action's label, naming exactly what a click
    /// does right now; nil when no open conversation is selected.
    var mergeActionTitle: String? {
        guard let selected, selected.state == "OPEN" else {
            return nil
        }

        if selected.isDraft {
            return "Ready"
        }
        if selected.isQueued {
            return "Queued"
        }
        if selected.hasAutomerge {
            return "Automerge"
        }
        if Self.isReadyToMerge(selected), isInStack == false || isStackBelowReady {
            return hasMergeQueue ? "Queue" : "Merge"
        }
        return isInStack ? "Waiting" : "Automerge"
    }

    /// Whether GitHub has scheduled merging, independent of readiness.
    var isMergeScheduled: Bool {
        selected?.hasAutomerge == true || selected?.isQueued == true
    }

    /// Draft and cancellation actions do not wait for stack readiness.
    var canMergeAction: Bool {
        guard let selected, selected.state == "OPEN" else {
            return false
        }

        return selected.isDraft || isMergeScheduled || isInStack == false
            || (canMergeStack && Self.isReadyToMerge(selected))
    }

    /// Why the merge action is in the state it is in.
    var mergeActionHelp: String {
        switch mergeActionTitle {
        case "Automerge":
            if selected?.hasAutomerge == true {
                return "Automerge is enabled on GitHub. Click to disable it"
            }
            return "Ask GitHub to merge when its requirements are met, using its merge queue if required"

        case "Queued":
            if isInStack {
                return "Queued on GitHub. Click to remove this pull request and those above it from the queue"
            }
            return "Queued for merging on GitHub. Click to remove it from the queue"

        case "Waiting":
            return "Wait for this pull request and every pull request below it to be ready to merge"

        case "Ready":
            return "Take this pull request out of draft"

        default:
            break
        }
        if isInStack {
            if let blocker = stack.stackingBlocker {
                return blocker
            }
            if isStackLinked == false {
                return "Open the pull requests below this one before merging the stack"
            }
            return "Merge or queue this pull request and every pull request below it"
        }
        return "Merge or queue this pull request on GitHub"
    }

    /// The present-tense form while the merge action runs.
    var mergeActionBusyTitle: String {
        switch mergeActionTitle {
        case "Ready":
            "Readying"

        case "Queued":
            "Dequeuing"

        case "Automerge":
            selected?.hasAutomerge == true ? "Disabling" : "Enabling"

        case "Queue":
            "Queueing"

        case "Merge":
            "Merging"

        default:
            "Waiting"
        }
    }

    /// What an in-app push sent, dimming Push and lighting Open PR
    /// until the branch moves on. Written only by the actions
    /// extension.
    struct PushedTip: Equatable {
        /// The branch pushed, so another entry of a stack never
        /// inherits the mark.
        let branch: String
        /// The commit pushed, since only the tip moving makes a
        /// push necessary again.
        let commit: String
    }

    /// Whether the entry in view is pushed as it stands. A count
    /// read before the push says otherwise for as long as it takes
    /// the next reading to land, which is what flipped Push and
    /// Open PR back and forth after a push.
    var isPushed: Bool {
        guard let mark = pushedTip, let branch = listedBranch ?? branchItem?.worktree.branch else {
            return false
        }

        return mark.branch == branch
    }

    /// Push makes sense with unpushed commits that this tab has not
    /// already pushed and a tip proven GPG signed; an unread tip
    /// dims the button rather than trusting the last answer, since
    /// a click on unverified commits could only end in a refusal.
    /// Nil upstream means nothing was ever pushed. A stack counts the
    /// selected branch, its bases and published branches above it.
    var canPush: Bool {
        if isInStack {
            return canPushStack
        }
        // One branch action at a time: a push pressed while a rebase
        // still runs failed against the branch mid-move.
        guard branchItem != nil, isBranchActionRunning == false, isGuardedDefaultBranch == false,
              isPushed == false, tipSignature == .signed, queuedBranchBlocker == nil
        else {
            return false
        }

        return hasUnpushedCommits
    }

    /// Whether the listed branch has commits the remote lacks: the
    /// stack's own reading when there is one, the worktree's
    /// upstream count otherwise.
    var hasUnpushedCommits: Bool {
        guard stacking.stack.isStacked, let listed = listedBranch else {
            return (branchItem?.aheadOfUpstream ?? 1) > 0
        }

        return stacking.unpushedBranches.contains(listed)
    }

    /// Why Push is in its current state, for the button's hover:
    /// with nothing to push that is the whole story, and signing
    /// only matters once commits are waiting.
    var pushHelp: String {
        if let queuedBranchBlocker {
            return queuedBranchBlocker
        }
        if isInStack {
            return pushStackHelp
        }
        guard isGuardedDefaultBranch == false else {
            return "This repository guards its default branch: put the work on a branch of its own "
                + "and open a pull request for it"
        }
        guard branchItem != nil, isPushed == false, hasUnpushedCommits else {
            return "Everything is already pushed"
        }

        return switch tipSignature {
        case .unread:
            "Checking that the tip commit is GPG signed; Push enables once it proves to be"

        case .unsigned:
            "The tip commit is not GPG signed; Sign and Push signs the branch before pushing"

        case .signed:
            "Push this branch's unpushed commits to origin; a failure reports to the Errors tab"
        }
    }

    /// The branch item's worktree with the checked-out branch
    /// substituted, so pushes and rebases act on what is actually
    /// checked out.
    var actionWorktree: Worktree? {
        worktree(on: currentBranch)
    }

    /// The same worktree with the listed entry's branch: a pull
    /// request is opened for the branch whose form was filled in,
    /// which in a stack need not be the one checked out.
    var listedWorktree: Worktree? {
        worktree(on: listedBranch)
    }

    /// The branch item's worktree as it stands on another of its
    /// branches; every entry of a stack is the same directory.
    func worktree(on branch: String?) -> Worktree? {
        guard let item = branchItem else {
            return nil
        }
        guard let branch, branch != item.worktree.branch else {
            return item.worktree
        }

        return Worktree(
            repositoryName: item.worktree.repositoryName,
            repositoryPath: item.worktree.repositoryPath,
            branch: branch,
            path: item.worktree.path,
        )
    }

    /// Whether a pull request is ready; an empty decision means no review is required.
    static func isReadyToMerge(_ summary: PullRequestSummary) -> Bool {
        summary.state == "OPEN" && summary.isDraft == false
            && summary.mergeable == "MERGEABLE" && summary.checks == "SUCCESS"
            && ["", "APPROVED"].contains(summary.reviewDecision)
    }
}
