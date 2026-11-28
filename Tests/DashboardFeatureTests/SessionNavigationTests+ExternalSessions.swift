@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

/// Sessions `sanductor new` asks the app for: the request is the
/// command's own JSON, and the answer is what the command reports.
extension SessionNavigationTests {
    @Test
    func `a spooled session starts through the form's own launch and answers with its failure`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let main = try #require(fixture.model.selection ?? fixture.model.groups.first?.items.first)
        fixture.model.select(main)
        fixture.model.showsNewSession = true

        // The empty runner answers nothing GitHub would, so each
        // source fails where the form's launch reads it.
        for (source, reference) in [("issue", "12"), ("pull-request", "34"), ("discussion", Self.discussion)] {
            let request = try Self.request(source: source, reference: reference, path: fixture.repository.path)
            #expect(await fixture.model.startSession(request)?.isEmpty == false)
        }

        // A script may ask for several: none takes the screen.
        #expect(fixture.model.selection?.id == main.id)
        #expect(fixture.model.showsNewSession)
        #expect(Set(fixture.model.launchFailures.values.map(\.draft.source)) == [.issue, .pullRequest, .discussion])
        #expect(fixture.model.launchFailures.values.allSatisfy { $0.draft.text == "Keep it small" })
    }

    @Test
    func `a spooled session nothing can start says why without launching`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let path = fixture.repository.path

        let unlisted = try Self.request(source: "issue", reference: "12", path: path + "-other")
        #expect(await fixture.model.startSession(unlisted) == "Not a repository Sanductor lists: " + path + "-other")
        let unknown = try Self.request(source: "issue", reference: "12", path: path, agent: "other")
        #expect(await fixture.model.startSession(unknown) == "Not an agent Sanductor knows: other")
        let unnumbered = try Self.request(source: "pull-request", reference: "twelve", path: path)
        #expect(await fixture.model.startSession(unnumbered) == "Not a number: twelve")
        // A pull request already launching is not one this request
        // started, so the command is not told that it did.
        fixture.model.launchProgresses[path + DashboardModel.placeholderMarker + "pr-34-running"] = LaunchProgress()
        let repeated = try Self.request(source: "pull-request", reference: "34", path: path)
        #expect(await fixture.model.startSession(repeated) == "Pull request #34 is already being started.")
        #expect(fixture.model.launchFailures.isEmpty)
    }

    // MARK: Private

    private static let discussion = "https://github.com/owner/repo/discussions/5"

    /// A request as the command spools it.
    private static func request(
        source: String, reference: String, path: String, agent: String = "claude",
    ) throws -> ExternalEdit {
        let json = try JSONSerialization.data(withJSONObject: [
            "path": path, "workingDirectory": "/", "processIdentifier": 1, "kind": "session",
            "session": [
                "agent": agent, "model": "", "effort": "", "source": source, "reference": reference,
                "context": "Keep it small",
            ],
        ])
        return try #require(ExternalEdit(id: "request", json: json))
    }
}
