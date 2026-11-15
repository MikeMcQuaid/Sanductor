import Foundation
import SanductorDomain
import Testing

struct WorkModeTests {
    @Test
    func `holiday hides work during working hours and snooze expires precisely`() {
        let date = Date(timeIntervalSince1970: 1_000)
        var mode = WorkMode()
        mode.isEnabled = true
        mode.startMinute = 0
        mode.endMinute = 0
        mode.weekdays = Set(1 ... 7)
        mode.organisations = ["Work"]
        mode.holidayUntil = date.addingTimeInterval(3_600)
        mode.snoozeUntil = date.addingTimeInterval(900)
        #expect(mode.hiddenOrganisations(at: date).isEmpty)
        #expect(mode.nextBoundary(after: date) == mode.snoozeUntil)
        #expect(mode.hiddenOrganisations(at: date.addingTimeInterval(900)) == ["work"])
        #expect(mode.nextBoundary(after: date.addingTimeInterval(900)) == mode.holidayUntil)
        #expect(mode.hiddenOrganisations(at: date.addingTimeInterval(3_600)).isEmpty)
    }

    @Test
    func `individual work repositories leave other repositories of their owner visible`() {
        var mode = WorkMode()
        mode.isEnabled = true
        mode.repositories = ["MikeMcQuaid/WebCoyote"]
        mode.holidayUntil = .distantFuture
        #expect(mode.hiddenRepositories(at: Date()) == ["mikemcquaid/webcoyote"])
    }

    @Test
    func `disabled work settings ignore a saved holiday and snooze`() {
        var mode = WorkMode()
        mode.organisations = ["Work"]
        mode.holidayUntil = .distantFuture
        #expect(mode.hiddenOrganisations(at: Date()).isEmpty)
        #expect(mode.nextBoundary(after: Date()) == nil)
    }

    @Test
    func `snoozing work visibility never restores notifications`() {
        let date = Date()
        var mode = WorkMode()
        mode.isEnabled = true
        mode.weekdays = []
        mode.repositories = ["Work/Project"]
        mode.snoozeUntil = date.addingTimeInterval(900)
        let work = Repository(name: "Project", path: "/work", fullName: "work/project")
        let personal = Repository(name: "Other", path: "/personal", fullName: "work/other")
        #expect(mode.hiddenRepositories(at: date).isEmpty)
        #expect(mode.silences(work, at: date))
        #expect(mode.silences(personal, at: date) == false)
        mode.holidayUntil = .distantFuture
        #expect(mode.isOnHoliday(at: date))
        mode.isEnabled = false
        #expect(mode.silences(work, at: date) == false)
        #expect(mode.isOnHoliday(at: date) == false)
    }

    @Test
    func `existing work settings decode with new settings unset`() throws {
        let data = Data(
            #"{"isEnabled":true,"organisations":["Work"],"weekdays":[2],"startMinute":540,"endMinute":1020}"#.utf8,
        )
        let mode = try JSONDecoder().decode(WorkMode.self, from: data)
        #expect(mode.organisations == ["Work"])
        #expect(mode.repositories.isEmpty)
        #expect(mode.holidayUntil == nil)
        #expect(mode.snoozeUntil == nil)
    }

    @Test(arguments: [
        ("2026-10-30T08:59:00Z", false), ("2026-10-30T09:00:00Z", true),
        ("2026-10-30T16:59:00Z", true), ("2026-10-30T17:00:00Z", false),
        ("2026-10-31T12:00:00Z", false),
    ])
    func `working hours include the start and exclude the end`(instant: String, working: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(ISO8601DateFormatter().date(from: instant))
        var mode = WorkMode()
        mode.organisations = ["Example"]
        #expect(mode.hiddenOrganisations(at: date, calendar: calendar).isEmpty)
        mode.isEnabled = true
        #expect(mode.isWorking(at: date, calendar: calendar) == working)
        #expect(mode.hiddenOrganisations(at: date, calendar: calendar) == (working ? [] : ["example"]))
        #expect(try #require(mode.nextBoundary(after: date, calendar: calendar)) > date)
    }

    @Test
    func `a Friday overnight work extends into Saturday`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var mode = WorkMode()
        mode.startMinute = 22 * 60
        mode.endMinute = 2 * 60
        let early = try #require(ISO8601DateFormatter().date(from: "2026-10-31T01:00:00Z"))
        let late = try #require(ISO8601DateFormatter().date(from: "2026-10-31T22:00:00Z"))
        #expect(mode.isWorking(at: early, calendar: calendar))
        #expect(mode.isWorking(at: late, calendar: calendar) == false)
    }

    @Test
    func `schedule previews mask tokens without altering surrounding text`() {
        for prefix in ["sntryu_", "sntrys_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_"] {
            let prompt = "TOKEN=" + prefix + String(repeating: "a", count: 64) + " run report"
            #expect(TokenRedaction.preview(prompt) == "TOKEN=" + prefix + "*** run report")
        }
        #expect(TokenRedaction.preview("ghp_example and ordinary prose") == "ghp_example and ordinary prose")
    }
}
