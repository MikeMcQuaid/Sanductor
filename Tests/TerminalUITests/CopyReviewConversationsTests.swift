import SanductorDomain
@testable import TerminalUI
import Testing

struct CopyReviewConversationsTests {
    @Test(arguments: [false, true])
    func `conversation copies resolve only after a successful copy`(resolve: Bool) async {
        let thread = ReviewThread(id: "open", path: "file", line: 1, isResolved: false, comments: [])
        var copied = false
        var resolved = [ReviewThread]()
        let button = CopyReviewConversationsButton(
            threads: [thread],
            onResolve: { threads in
                #expect(copied)
                resolved = threads
            },
            pendingResolution: { _ in false },
        )
        await button.copy(resolve: resolve) { _ in false }
        #expect(resolved.isEmpty)
        await button.copy(resolve: resolve) { _ in copied = true; return true }
        #expect(resolved == (resolve ? [thread] : []))
    }

    @Test
    func `conversation resolution uses the copied snapshot of unmarked findings`() async {
        let open = ReviewThread(id: "open", path: "file", line: 1, isResolved: false, comments: [])
        let pending = ReviewThread(id: "pending", path: "file", line: 1, isResolved: false, comments: [])
        let closed = ReviewThread(id: "closed", path: "file", line: 1, isResolved: true, comments: [])
        var isPending = true
        var resolved = [ReviewThread]()
        let button = CopyReviewConversationsButton(
            threads: [open, pending, closed],
            onResolve: { resolved = $0 },
            pendingResolution: { $0.id == pending.id && isPending },
        )
        await button.copy(resolve: true) { _ in isPending = false; return true }
        #expect(resolved == [open])
    }
}
