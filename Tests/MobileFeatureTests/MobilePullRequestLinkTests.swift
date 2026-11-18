@testable import MobileFeature
import SanductorDomain
import Testing

struct MobilePullRequestLinkTests {
    @Test(arguments: [true, false], [
        "https://github.com/owner/repo/pull/42",
        "https://github.com.evil.example/owner/repo/pull/42",
    ])
    func `PR links try the installed app before falling back to the browser`(hasApp: Bool, url: String) async {
        let pullRequest = SidebarPullRequest(PullRequestSummary(
            number: 42,
            title: "",
            url: url,
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
        ))
        var attempts = [Bool]()
        await pullRequest.open { target, universalLinksOnly in
            #expect(target.absoluteString == url)
            attempts.append(universalLinksOnly)
            return universalLinksOnly == false || hasApp
        }
        if pullRequest.webURL == nil {
            #expect(attempts.isEmpty)
        } else {
            #expect(attempts == (hasApp ? [true] : [true, false]))
        }
    }
}
