import AppKit
@testable import DashboardFeature
import SanductorData
import SwiftUI
import Testing

extension SessionNavigationTests {
    @Test
    func `all GitHub source selectors share their compact empty state`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            "agentKind": "claude", "agentModel": "sonnet", "agentEffort": "high", AgentSessionForm.promptKey: "Context",
        ])
        defer { restore() }
        var heights = [CGFloat]()
        for source in [AgentSessionForm.PromptSource.issue, .pullRequest, .advisory, .discussion] {
            fixture.model.launchRetry = LaunchRetry(
                repositoryPath: fixture.repository.path,
                worktreePath: nil,
                draft: LaunchDraft(text: "Context", source: source, agent: .claudeCode, options: AgentLaunchOptions()),
            )
            let form = AgentSessionForm(
                model: fixture.model, repository: fixture.repository, submitTitle: "Start", submitHelp: "Start",
            ) { _ in Issue.record("An empty source must not launch an agent") }
            let host = NSHostingView(rootView: form.frame(width: 600).fixedSize(horizontal: false, vertical: true))
            let window = Fixture.window(hosting: host)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(100))
            #expect(fixture.model.launchRetry == nil)
            host.layoutSubtreeIfNeeded()
            heights.append(host.fittingSize.height)
        }
        let expected = try #require(heights.first)
        #expect(heights.allSatisfy { abs($0 - expected) < 1 })
    }
}
