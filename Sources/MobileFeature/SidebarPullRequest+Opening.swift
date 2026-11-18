import Foundation
import SanductorDomain

extension SidebarPullRequest {
    /// Leaves private repository authentication to the app or browser that opens the PR.
    func open(using openURL: (URL, Bool) async -> Bool) async {
        guard let url = webURL else {
            return
        }

        if await openURL(url, true) == false {
            _ = await openURL(url, false)
        }
    }
}
