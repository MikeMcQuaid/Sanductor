import Foundation
@testable import PRFeature
import SanductorData
import Synchronization
import Testing

/// A tip that reads unsigned after a rebase is read again after a
/// moment, then rebased once more, before anyone is asked to press
/// anything.
extension PullRequestsModelTests {
    @Test
    func `a failed rebase retry invalidates an earlier signed tip`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        await model.reload()
        #expect(model.canPush)
        var attempts = 0
        model.performRebase = { _ in
            attempts += 1
            if attempts == 2 {
                throw CocoaError(.fileWriteNoPermission)
            }
            return "origin/main"
        }
        model.checkSignature = { _, _ in false }

        #expect(await model.rebaseSigned() == false)
        #expect(attempts == 2)
        #expect(model.canPush == false)
    }

    @Test(arguments: [false, true])
    func `a signature read for a replaced tip leaves its newer refresh in control`(duringConfirmation: Bool) async {
        let row = item(branch: "feature", ahead: 1)
        let model = makeModel(items: [row])
        var tip = "rebased"
        var verified = false
        model.fetchTipCommit = { _ in
            let read = tip
            if duringConfirmation, verified, tip == "rebased" {
                tip = "replacement"
                await model.refreshWorktreeFacts(row.worktree)
            }
            return read
        }
        model.checkSignature = { _, commit in
            #expect(commit == tip)
            guard commit == "rebased" else {
                return false
            }

            verified = true
            if duringConfirmation == false {
                tip = "replacement"
                await model.refreshWorktreeFacts(row.worktree)
            }
            return true
        }

        #expect(await model.rebaseSigned() == false)
        #expect(model.tipSignature == .unsigned)
        #expect(model.canPush == false)
    }

    @Test
    func `the second rebase also waits for its signature`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        var rebases = 0
        var reads = 0
        model.performRebase = { _ in rebases += 1; return "origin/main" }
        model.checkSignature = { _, _ in
            guard rebases == 2 else {
                return false
            }

            reads += 1
            return reads > 1
        }

        #expect(await model.rebaseSigned())
        #expect(rebases == 2)
    }

    @Test(arguments: [false, true])
    func `a sidebar update during the final rebase read cannot undo verification`(duringSignature: Bool) async {
        let row = item(branch: "feature", ahead: 1)
        let model = makeModel(items: [row])
        var refreshed = false
        model.fetchRebaseNeed = { _ in
            if duringSignature == false {
                model.items = [item(branch: "feature", ahead: 2)]
                refreshed = true
            }
            return .nothing
        }
        model.checkSignature = { _, _ in
            if duringSignature, refreshed == false {
                refreshed = true
                await model.refreshWorktreeFacts(row.worktree)
            }
            return refreshed
        }

        #expect(await model.rebaseSigned())
        #expect(model.tipSignature == .signed)
    }

    @Test
    func `sign and push does not reload the PR between signing and pushing`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        var signed = false
        var pushed = false
        model.checkSignature = { _, _ in signed }
        model.fetchRebaseNeed = { _ in signed ? .nothing : .sign }
        model.performRebase = { _ in signed = true; return "origin/main" }
        model.performPush = { _ in pushed = true; return .origin }
        model.fetchList = { _, _ in
            #expect(signed == false || pushed)
            return []
        }
        await model.reload()
        #expect(await model.publish())
        #expect(pushed)
    }

    @Test
    func `a tip read too early is read again, not rebased again`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        let readsAfterRebase = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        // The first read after the rebase lands before the rebase
        // did; the next reads it signed.
        model.checkSignature = { _, _ in
            guard rebases.withLock({ $0 }) > 0 else {
                return false
            }

            return readsAfterRebase.withLock { reads in
                reads += 1
                return reads >= 2
            }
        }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(rebases.withLock { $0 } == 1)
        #expect(model.tipSignature == .signed)
    }

    @Test
    func `a tip still unsigned after a rebase and a second read is rebased once more`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        // Unsigned however often it is read until the second rebase.
        model.checkSignature = { _, _ in rebases.withLock { $0 } >= 2 }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(rebases.withLock { $0 } == 2)
        #expect(model.tipSignature == .signed)
    }

    @Test
    func `a tip unsigned after two rebases is reported, not rebased again`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        model.checkSignature = { _, _ in false }
        await model.reload()

        #expect(await model.rebaseSigned() == false)
        #expect(rebases.withLock { $0 } == 2)
    }
}
