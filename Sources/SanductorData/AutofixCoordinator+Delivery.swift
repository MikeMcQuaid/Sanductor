import SanductorDomain

extension AutofixCoordinator {
    func ready(_ target: AutofixDriver.Target, head: String, context: AutofixContext) async -> Bool {
        guard let reason = await context.driver.waitReason(target, head) else {
            return true
        }

        context.store.update { $0.pullRequestAutomation[context.key]?.pending = reason }
        return false
    }

    func canDeliver(
        _ candidate: AutofixCandidate,
        state: PullRequestAutomation,
        capture: (summary: PullRequestSummary, head: String),
        target: AutofixDriver.Target,
        context: AutofixContext,
    ) async throws -> Bool {
        let driver = context.driver
        let (summary, head) = capture
        guard let fresh = try await driver.summary(state, true), fresh.state == "OPEN", state.matches(fresh),
              fresh.headBranch == summary.headBranch, fresh.headCommit == summary.headCommit,
              let checked = try await deliveryCandidate(
                  state: state,
                  summary: fresh,
                  head: head,
                  target: target,
                  driver: driver,
                  remoteOnly: target.allowsWorking,
              ),
              checked == candidate,
              let final = try await driver.summary(state, true), state.matches(final), final.state == "OPEN",
              final.headCommit == fresh.headCommit, final.headBranch == fresh.headBranch
        else {
            context.store.update { value in
                value.pullRequestAutomation[context.key]?.pending = "Waiting: captured feedback changed"
            }
            return false
        }
        guard await ready(target, head: head, context: context) else {
            return false
        }

        if candidate.sources.contains(.localReview), state.isPreparingExistingWork == false {
            guard let collection = try await driver.collect(state, target, false),
                  collection.isPending == false, collection.failure == nil,
                  collection.id == state.collection?.id
            else {
                return false
            }
        }
        return true
    }

    func deliver(
        _ attempt: AutofixAttempt,
        prompt: String,
        context: AutofixContext,
        marks: [String: PendingThreadResolution] = [:],
    ) async {
        do {
            try await context.driver.deliver(attempt, prompt)
            try context.store.updatePersisting { value in
                guard value.pullRequestAutomation[context.key]?.attempt?.id == attempt.id else {
                    return
                }

                for (id, mark) in marks where attempt.localThreadIDs.contains(id) == false {
                    if value.pullRequestAutomation[context.key]?.resolutions[id]?.commentID != mark.commentID {
                        value.pullRequestAutomation[context.key]?.resolutions[id] = PendingThreadResolution(
                            head: mark.head, commentID: mark.commentID, autofixAttemptID: attempt.id,
                        )
                    }
                }

                value.pullRequestAutomation[context.key]?.pending = attempt.commitRequestedHead == nil
                    ? "Fix-and-commit prompt sent; follow progress in the agent pane"
                    : "Commit-only prompt sent; waiting for the agent to commit existing fixes"
            }
        } catch {
            context.store.update { value in
                value.pullRequestAutomation[context.key]?.lastResult = "Delivery unconfirmed; it will not be repeated. "
                    + error.localizedDescription
            }
        }
    }
}
