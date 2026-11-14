@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

@MainActor
extension SessionNavigationTests {
    @Test
    func `work organisations exclude users and retain selected outside organisations`() async {
        let fixture = Fixture(runner: WorkOrganisationRunner())
        defer { fixture.close() }
        let found = await fixture.model.workModeOrganisations(selected: ["mikemcquaid", "OtherUser", "OutsideOrg"])
        #expect(found.choices == ["Homebrew", "OutsideOrg"])
        #expect(found.users == ["MikeMcQuaid", "OtherUser"])
    }

    @Test(arguments: [false, true])
    func `work mode hides repositories and selection without dropping running state`(individual: Bool) throws {
        let saved = AppSettings.workMode
        defer { AppSettings.workMode = saved }
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        let model = fixture.model
        let original = try #require(model.groups.first)
        model.groups = [
            RepositoryGroup(
                repository: Repository(name: "repo", path: original.repository.path, fullName: "Work/repo"),
                items: original.items,
            ),
        ]
        model.selection = original.items.first
        var mode = WorkMode()
        mode.isEnabled = true
        mode.organisations = individual ? [] : ["work"]
        mode.repositories = individual ? ["work/repo"] : []
        mode.weekdays = []
        AppSettings.workMode = mode
        model.refreshWorkMode()
        #expect(model.visibleGroups.isEmpty)
        #expect(model.publishedSidebar.first?.isHidden == true)
        #expect(model.selection == nil)
        #expect(model.groups.first?.items.count == original.items.count)
        model.selection = original.items.first
        #expect(model.selection == nil)
        mode.isEnabled = false
        AppSettings.workMode = mode
        model.refreshWorkMode()
        #expect(model.visibleGroups == model.groups)
        #expect(model.publishedSidebar.first?.isHidden == false)
    }
}

// MARK: - WorkOrganisationRunner

private struct WorkOrganisationRunner: ProcessRunner {
    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        let output =
            if arguments.contains("user") {
                "MikeMcQuaid"
            } else if arguments.contains("user/orgs?per_page=100") {
                "Homebrew"
            } else if arguments.contains("users/OutsideOrg") {
                "Organization"
            } else {
                "User"
            }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}
