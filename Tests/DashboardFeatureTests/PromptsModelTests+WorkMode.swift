@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

extension PromptsModelTests {
    @Test(arguments: [false, true])
    func `holidays skip work schedules while outside working hours still runs them`(holiday: Bool) async throws {
        let fixture = SessionNavigationTests.Fixture()
        defer { fixture.close() }
        var work = prompt()
        work.repositoryPath = "/work"
        var personal = prompt()
        personal.repositoryPath = "/personal"
        var repository = CachedRepository()
        repository.path = "/work"
        repository.fullName = "Work/Project"
        fixture.model.store.update { metadata in
            metadata.savedPrompts = [work, personal]
            metadata.cachedSidebar = [repository]
        }
        let model = makeModel(fixture)
        var mode = WorkMode()
        mode.isEnabled = true
        mode.weekdays = []
        mode.organisations = ["work"]
        mode.holidayUntil = holiday ? .distantFuture : nil
        mode.snoozeUntil = .distantFuture
        model.workMode = { mode }
        var launched = [String]()
        model.launch = { prompt, _ in launched.append(prompt.repositoryPath); return "session" }
        await model.runDue()
        #expect(launched == (holiday ? ["/personal"] : ["/work", "/personal"]))
        #expect(try #require(model.prompts.first?.nextRun) > model.now())
        #expect(model.prompts.first?.lastRun == (holiday ? nil : model.now()))
        if holiday {
            await model.start(work)
            #expect(launched == ["/personal"])
            mode.holidayUntil = nil
            await model.runDue()
            #expect(launched == ["/personal"])
        }
    }
}
