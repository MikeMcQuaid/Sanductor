import Foundation
import SanductorDomain
import TerminalUI

/// Opening a pull request, and telling both surfaces about it at
/// once: the sidebar's row and this pane read one per-branch cache,
/// so what the form opens is on the row before any poll. Split from
/// the actions for length.
extension PullRequestsModel {
    var canOpenPullRequest: Bool {
        isOpening == false && isBranchActionRunning == false && isDefaultBranch == false
            && branchItem != nil && (isInStack == false || stack.stackingBlocker == nil) && unopenedBelow == nil
            && prTitle.trimmingCharacters(in: .whitespaces).isEmpty == false && templateUnedited == false
            && (isFullyPushed || canPublish)
    }

    /// Paints the pushed branches' pull requests as awaiting their
    /// checks, in the caches every row and pane read and in what
    /// this tab already holds, so the state shows the moment the
    /// push lands rather than the last run's verdict for the minute
    /// GitHub takes to see the new commits.
    func markChecksPending(for branches: [String]) {
        pullRequests.markChecksPending(repositoryPath: repository.path, branches: branches)
        let pushed = Set(branches)
        stacking.unpushedBranches.removeAll(where: pushed.contains)
        Task {
            await resolveMarkedReviews(pushed, nil)
        }
        summaries = summaries.map { pushed.contains($0.headBranch) && $0.state == "OPEN" ? $0.awaitingChecks() : $0 }
        if let selected, pushed.contains(selected.headBranch), selected.state == "OPEN" {
            self.selected = selected.awaitingChecks()
        }
        // The rows read the caches just painted: now, not after the
        // reading the push also asks for.
        UtilityTabTarget.pullRequestCacheChanged()
    }

    /// Pushes through the listed entry and reports the branches sent.
    func pushSelectedStack(_ worktree: Worktree) async -> Bool {
        guard unpushedBelow == nil else {
            setStatus("Not pushed.", detail: pushStackHelp)
            return true
        }

        do {
            let pushed = try await stacking.push(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            markChecksPending(for: pushed)
            if let tip = await fetchTipCommit(worktree) {
                pushedTip = PushedTip(branch: worktree.branch, commit: tip)
            }
            recordFinished(.pushed, branch: worktree.branch)
            note("Pushed " + Self.named(pushed) + ".")
            UtilityTabTarget.requestSidebarRefresh()
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// Opens the pull request from the form's title and body, with
    /// the template appended below the body after an empty line;
    /// false opens the errors surface. Unpublished commits go through
    /// the shared preparation and push action before creation.
    func createPullRequest() async -> Bool {
        guard isOpening == false, isBranchActionRunning == false, let worktree = listedWorktree else {
            return true
        }

        if let below = unopenedBelow {
            setStatus("Not opened.", detail: "Open a pull request for `" + below + "` below this branch first")
            return true
        }

        let title = prTitle.trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            report("The pull request needs a title.")
            return false
        }

        let body = Self.joined(body: prBody, template: prTemplate)
        let labels = prLabels
        let isDraft = prIsDraft
        isOpening = true
        defer { isOpening = false }
        if isFullyPushed == false {
            guard canPublish else {
                setStatus("Not opened.", detail: publishHelp)
                return true
            }
            guard await publish() else {
                return false
            }
            guard isFullyPushed else {
                return true
            }
        }
        do {
            let url = try await performCreate(worktree, title, body, labels, isDraft)
            finishOpening(url: url, title: title, worktree: worktree, isDraft: isDraft)
            Task {
                do {
                    try await performLinkStack(worktree)
                } catch {
                    report("Stacking on GitHub failed: " + error.localizedDescription)
                }
                await assignClosingIssues(pullRequestURL: url)
            }
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    private func finishOpening(url: String, title: String, worktree: Worktree, isDraft: Bool) {
        pullRequests.invalidateListings(repositoryPath: repository.path)
        UtilityTabTarget.requestSidebarRefresh()
        let created = Self.created(
            url: url,
            title: title,
            worktree: worktree,
            base: stack.parent(of: worktree.branch) ?? defaultBranch,
            listed: summaries,
            isDraft: isDraft,
        )
        if let created {
            if summaries.contains(where: { $0.number == created.number }) == false {
                summaries.insert(created, at: 0)
            }
            cacheCreated(created, branch: worktree.branch)
            select(created)
        }
        loadingDraft = true
        prTitle = ""
        prLabels = []
        prBody = ""
        prTemplate = originalTemplate
        loadingDraft = false
        clearDraft()
    }

    private func assignClosingIssues(pullRequestURL: String) async {
        note("Opened pull request " + pullRequestURL)
        do {
            try await performAssignClosingIssues(pullRequestURL)
        } catch {
            let firstFailure = error.localizedDescription
            PerformanceLog.recordMessage("Assigning closing issues failed; retrying: " + firstFailure, isError: false)
            do {
                try await performAssignClosingIssues(pullRequestURL)
            } catch {
                report("Opened " + pullRequestURL + ", but assigning its closing issues failed: " + firstFailure
                    + ". Retry failed: " + error.localizedDescription)
            }
        }
    }

    /// Pushes the checked-out branch; false means the push failed
    /// and the errors tab should open with the cause.
    func push() async -> Bool {
        guard let worktree = listedWorktree else {
            return true
        }

        // The menu bar's Push reaches this without a button to dim,
        // and a push to the default branch goes round the pull
        // request the rest of this tab is for.
        guard isGuardedDefaultBranch == false else {
            setStatus(
                "Not pushed: the default branch is guarded.",
                detail: "the default branch is protected or wants a pull request; work belongs "
                    + "on a branch of its own",
            )
            return true
        }

        isBranchActionRunning = true
        defer { isBranchActionRunning = false }
        // The tip can change during preparation, so verify it again
        // before pushing and let the combined action retry signing.
        guard await checkTipSigned(worktree) else {
            tipSignature = .unsigned
            rebaseNeed = await fetchRebaseNeed(worktree)
            setStatus(
                "Not pushed: the tip commit is unsigned.",
                detail: "The tip commit of `" + worktree.branch
                    + "` is not GPG signed; check the signing key, then use Sign and Push again.",
            )
            return true
        }

        do {
            // Publish the listed entry with its bases and update published branches above it.
            guard stacking.stack.isStacked == false else {
                return await pushSelectedStack(worktree)
            }

            let destination = try await performPush(worktree)
            pullRequests.invalidateListings(repositoryPath: repository.path)
            markChecksPending(for: [worktree.branch])
            if let tip = await fetchTipCommit(worktree) {
                pushedTip = PushedTip(branch: worktree.branch, commit: tip)
            }
            recordFinished(.pushed, branch: worktree.branch)
            note(Self.describe(push: destination))
            UtilityTabTarget.requestSidebarRefresh()
            refreshAfterPush()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    /// What a just-opened pull request is, for the row and the pane:
    /// the listing's own answer where GitHub has caught up, else the
    /// bare facts the form knows, which the next fetch replaces.
    static func created(
        url: String,
        title: String,
        worktree: Worktree,
        base: String?,
        listed: [PullRequestSummary],
        isDraft: Bool = false,
    ) -> PullRequestSummary? {
        guard let number = number(inURL: url) else {
            return nil
        }

        // The creation's own answer is the pull request's page, so
        // opening it in a browser, and the checks link beside it,
        // work before any fetch has been near it.
        return listed.first { $0.number == number } ?? PullRequestSummary(
            number: number,
            title: title,
            url: url,
            headBranch: worktree.branch,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            baseBranch: base ?? "",
            state: "OPEN",
            isDraft: isDraft,
        )
    }

    /// Records a new pull request where both surfaces read it, and
    /// asks the sidebar to repaint from it at once.
    func cacheCreated(_ summary: PullRequestSummary, branch: String) {
        pullRequests.rememberBranchSummary(summary, repositoryPath: repository.path, branch: branch)
        UtilityTabTarget.pullRequestCacheChanged()
    }
}
