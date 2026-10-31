@testable import SanductorData
import Testing

struct AutofixStreamingTests {
    @Test(arguments: [false, true])
    func `optional failures follow the shared checks selection`(include: Bool) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        var driver = await fixture.driver()
        driver.includesOptionalChecks = { _ in include }
        await fixture.update { state in
            state.checkConclusion = "SUCCESS"
            state.optionalConclusion = "FAILURE"
            state.checksComplete = false
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: driver)
        #expect(await fixture.state.deliveries.count == (include ? 1 : 0))
    }

    @Test(arguments: ["blocked", "stopped", "session", "head"])
    func `supplemental feedback rechecks the loop and target`(change: String) async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("first")]
            state.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        await fixture.update { state in
            state.activity = change == "blocked" ? .blocked : .working
            state.hasSession = change != "session"
            if change == "head" {
                state.freshHead = "different"
            }
            state.comments.append(AutofixFixture.thread("second", comment: "second"))
        }
        if change == "stopped" {
            fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.stopLoop() }
        }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(fixture.store
            .load()
            .pullRequestAutomation[AutofixFixture.key]?
            .handledEvents
            .contains("comment:second") == false)
    }

    @Test
    func `available failures and reviews do not wait for other jobs or reviewers`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixCI = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixBots = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.checksComplete = false
            state.optionalComplete = false
            state.requestedReviewers = ["coderabbitai"]
            state.comments = [AutofixFixture.thread("review", author: "coderabbitai", type: "Bot")]
        }
        await AutofixCoordinator().refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 1)
        #expect(await fixture.state.deliveries.first?.sources == [.checks, .codeRabbit])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["review"] != nil)
    }

    @Test
    func `new feedback joins a working attempt once and stale results cannot complete it`() async throws {
        let fixture = try AutofixFixture()
        fixture.store.update { metadata in
            metadata.pullRequestAutomation[AutofixFixture.key]?.autofixReviews = true
            metadata.pullRequestAutomation[AutofixFixture.key]?.startLoop()
        }
        await fixture.update { state in
            state.comments = [AutofixFixture.thread("first")]
            state.writers = ["human"]
        }
        let coordinator = AutofixCoordinator()
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        let first = try #require(await fixture.state.deliveries.first)
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.resolutions["first"] = nil }
        await fixture.update { state in
            state.activity = .working
            state.isDirty = true
            state.comments.append(AutofixFixture.thread("second", comment: "second"))
        }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(await fixture.state.deliveries.count == 2)
        let latest = try #require(await fixture.state.deliveries.last)
        #expect(latest.id != first.id)
        #expect(Set(latest.threads.keys) == ["first", "second"])
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["first"] == nil)
        #expect(await fixture.state.prompts.last?.contains("Fix first") == false)
        await fixture.update { state in
            state.activity = .done
            state.isDirty = false
            state.result = AutofixResult(
                attemptID: first.id, head: first.head, commit: "head", addressedThreadIDs: ["first"],
            )
        }
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.attempt?.id == latest.id)
        await fixture.complete(addressed: ["first", "second"])
        await coordinator.refresh(store: fixture.store, driver: fixture.driver())
        #expect(fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.resolutions["first"] == nil)
    }
}
