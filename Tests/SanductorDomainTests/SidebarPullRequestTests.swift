import Foundation
import SanductorDomain
import Testing

struct SidebarPullRequestTests {
    @Test(arguments: ["OPEN", "CLOSED", "MERGED"], ["CONFLICTING", "MERGEABLE", "UNKNOWN", ""])
    func `phone snapshots include only visible conflicts`(state: String, mergeable: String) throws {
        let data = try JSONEncoder().encode(SidebarPullRequest(PullRequestSummary(
            number: 42,
            title: "",
            url: "https://github.com/owner/repo/pull/42",
            headBranch: "work",
            mergeable: mergeable,
            reviewDecision: "",
            checks: "",
            state: state,
        )))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let details = try #require(json["details"] as? [String: Any])
        #expect(details["mergeable"] as? String == (state == "OPEN" && mergeable == "CONFLICTING" ? mergeable : nil))
    }

    @Test
    func `older PR snapshots decode without conflict information`() throws {
        let projection = try JSONDecoder().decode(SidebarPullRequest.self, from: Data(#"""
        {"number":42,"url":"https://github.com/owner/repo/pull/42",
         "details":{"state":"OPEN","isDraft":false,"isQueued":false,
                    "checks":"SUCCESS","checksDescription":"success","reviewDecision":"APPROVED"}}
        """#.utf8))
        #expect(projection.details?.stateLabel == "Open")
        #expect(projection.webURL?.absoluteString == "https://github.com/owner/repo/pull/42")
    }

    @Test
    func `PR status crosses the sandbox boundary without a public visibility requirement`() throws {
        let data = try JSONEncoder().encode(SidebarPullRequest(PullRequestSummary(
            number: 42,
            title: "Private title",
            url: "https://github.com/owner/repo/pull/42",
            headBranch: "work",
            mergeable: "CONFLICTING",
            reviewDecision: "CHANGES_REQUESTED",
            checks: "FAILURE",
            state: "CLOSED",
        )))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("CHANGES_REQUESTED"))
        #expect(json.contains("FAILURE"))
        #expect(json.contains("CLOSED"))
    }

    @Test
    func `old sidebar entries decode without PR details`() throws {
        let entry = try JSONDecoder().decode(SidebarEntry.self, from: Data(#"""
        {"target":{"repository":"repo","repositoryPath":"/repo","branch":"work","path":"/tree"},
         "status":"Branch"}
        """#.utf8))
        #expect(entry.pullRequest == nil)
    }

    @Test(arguments: [
        ("https://github.com/owner/repo/pull/1234", true),
        ("https://github.com/owner/repo/pull/999", false),
        ("https://github.com/owner/repo/issues/1234", false),
        ("http://github.com/owner/repo/pull/1234", false),
        ("https://github.com.evil.example/owner/repo/pull/1234", false),
        ("https://user:secret@github.com/owner/repo/pull/1234", false),
        ("file:///private/file", false),
        ("javascript:alert(1)", false),
    ])
    func `only GitHub HTTPS PR links open from a shared snapshot`(url: String, valid: Bool) throws {
        let projection = SidebarPullRequest(PullRequestSummary(
            number: 1_234,
            title: "Private title",
            url: url,
            headBranch: "work",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            body: "Private conversation",
            optionalFailures: 1,
        ))
        let data = try JSONEncoder().encode(projection)
        let decoded = try JSONDecoder().decode(SidebarPullRequest.self, from: data)
        #expect(decoded == projection)
        #expect((decoded.webURL != nil) == valid)
        #expect(decoded.details?.checksDescription == "passing; 1 optional check failing")
        #expect(String(data: data, encoding: .utf8)?.contains("Private") == false)
    }

    @Test(arguments: [
        ("OPEN", false, false, "Open"),
        ("OPEN", true, false, "Draft"),
        ("OPEN", false, true, "Queued"),
        ("CLOSED", false, false, "Closed"),
        ("MERGED", false, false, "Merged"),
    ])
    func `phone PR state labels distinguish drafts and the merge queue`(
        state: String,
        draft: Bool,
        queued: Bool,
        label: String,
    ) {
        let projection = SidebarPullRequest(PullRequestSummary(
            number: 1,
            title: "",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            isDraft: draft,
            isQueued: queued,
        ))
        #expect(projection.details?.stateLabel == label)
    }
}
