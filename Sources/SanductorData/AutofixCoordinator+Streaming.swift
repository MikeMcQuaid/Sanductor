import SanductorDomain

extension AutofixCoordinator {
    func gatherRemote(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws -> Bool {
        guard state.isAutomatic, state.hasRemoteSources, state.attempt?.rebase == nil,
              summary.mergeable != "CONFLICTING", let remoteHead = summary.headCommit,
              let head = await context.driver.head(target)
        else {
            return false
        }

        if head != remoteHead,
           await state.acceptsFeedback(
               from: remoteHead, contains: { await context.driver.containsHead(target, $0) },
           ) == false
        {
            return false
        }
        if let attempt = state.attempt {
            guard attempt.worktreePath == target.worktree.path, attempt.branch == target.worktree.branch,
                  attempt.sessionName == target.session.name, attempt.paneID == target.session.paneID
            else {
                return false
            }
        }
        var selection = state
        selection.autofixLocalReviews = false
        guard var feedback = try await candidate(
            state: selection, summary: summary, head: head, fresh: false, driver: context.driver,
        ) else {
            return false
        }

        var receiving = target
        receiving.allowsWorking = true
        receiving.allowsUncommitted = true
        guard await ready(receiving, head: head, context: context) else {
            return true
        }

        if state.attempt == nil, state.isLocalStage, target.session.activity != .working {
            let collection = state.isPreparingExistingWork ? state.collection
                : try await context.driver.collect(state, target, false)
            if state.isPreparingExistingWork
                || (collection?.isPending == false && collection?.failure == nil && collection?.review != nil)
            {
                selection.autofixLocalReviews = true
                selection.feedbackWorktreePath = target.worktree.path
                if let combined = try await candidate(
                    state: selection, summary: summary, head: head, fresh: false, driver: context.driver,
                ) {
                    feedback = combined
                }
            }
        }
        try await send(feedback, summary: summary, head: head, target: receiving, context: context, remoteOnly: true)
        return true
    }
}
