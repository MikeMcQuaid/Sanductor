import SanductorDomain

extension AutofixCoordinator {
    func resolveMarked(
        state: PullRequestAutomation,
        head: String,
        context: AutofixContext,
    ) async throws {
        let driver = context.driver
        guard state.resolutions.isEmpty == false else {
            return
        }

        let cached = try await driver.threads(state, false)
        let changed = cached.contains { thread in
            state.resolutions[thread.resolveID].map { mark in
                thread.isResolved || thread.comments.last?.id != mark.commentID
            } ?? false
        }
        if changed || state.resolutions.values.contains(where: { $0.requested == false && $0.head != head }) {
            try await resolveAfterPush(state: state, context: context)
        }
    }

    func resolveAfterPush(
        state: PullRequestAutomation, context: AutofixContext, branches: Set<String> = [],
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        async let readingThreads = driver.threads(state, true)
        guard let fresh = try await driver.summary(state, true), fresh.url == state.url, fresh.state == "OPEN",
              branches.isEmpty || branches.contains(fresh.headBranch),
              let head = fresh.headCommit, head.isEmpty == false
        else {
            return
        }

        let threads = try await readingThreads
        for (id, mark) in state.resolutions {
            guard let thread = threads.first(where: { $0.resolveID == id }) else {
                continue
            }

            if thread.isResolved || thread.comments.last?.id != mark.commentID {
                try store.updatePersisting { value in
                    guard value.pullRequestAutomation[key]?.resolutions[id] == mark else {
                        return
                    }

                    if thread.isResolved {
                        Self.rememberResolved(thread, for: state, in: &value)
                    }
                    value.pullRequestAutomation[key]?.resolutions[id] = nil
                    value.pullRequestAutomation[key]?.lastResult = thread.isResolved
                        ? "Conversation resolved" : "New comments arrived; the conversation was left open"
                }
                await context.resolutionChanged?()
                continue
            }
            guard mark.requested == false, head != mark.head else {
                continue
            }

            if let commit = mark.fixCommit, await driver.containsFix(state, commit, head) == false {
                continue
            }

            var claimed = false
            try store.updatePersisting { metadata in
                guard metadata.pullRequestAutomation[key]?.resolutions[id] == mark else {
                    return
                }

                metadata.pullRequestAutomation[key]?.resolutions[id]?.requested = true
                claimed = true
            }
            guard claimed else {
                continue
            }

            await resolve(thread, mark: mark, state: state, context: context)
        }
    }

    private func resolve(
        _ thread: ReviewThread, mark: PendingThreadResolution, state: PullRequestAutomation, context: AutofixContext,
    ) async {
        let id = thread.resolveID
        let key = context.key
        let store = context.store
        let driver = context.driver
        do {
            try await driver.resolve(state, id)
            try store.updatePersisting { value in
                Self.rememberResolved(thread, for: state, in: &value)
                var claimed = mark
                claimed.requested = true
                if value.pullRequestAutomation[key]?.resolutions[id] == claimed {
                    value.pullRequestAutomation[key]?.resolutions[id] = nil
                    value.pullRequestAutomation[key]?.lastResult = "Resolved a marked conversation after the push"
                }
            }
            await context.resolutionChanged?()
        } catch {
            store.update { value in
                value.pullRequestAutomation[key]?.lastResult = "Resolution unconfirmed; mark again to retry. "
                    + error.localizedDescription
            }
        }
    }

    private static func rememberResolved(
        _ thread: ReviewThread, for state: PullRequestAutomation, in value: inout AppMetadata,
    ) {
        let cacheKey = AppMetadata.threadsKey(repositoryPath: state.repositoryPath, number: state.number)
        var threads = value.threadsCache[cacheKey]?.threads ?? []
        if let index = threads.firstIndex(where: { $0.resolveID == thread.resolveID }) {
            threads[index].isResolved = true
        } else {
            var resolved = thread
            resolved.isResolved = true
            threads.append(resolved)
        }
        value.threadsCache[cacheKey] = CachedThreads(threads: threads)
    }
}
