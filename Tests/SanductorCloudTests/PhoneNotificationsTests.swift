@testable import SanductorCloud
import Testing

struct PhoneNotificationsTests {
    @Test
    func `a process not signed for iCloud gets no client rather than trapping`() {
        // Only the Mac reads its signature; the iPhone always has one.
        #if os(macOS)
            #expect(PhoneNotifications(bundleIdentifier: "com.mikemcquaid.Sanductor") == nil)
        #endif
        #expect(PhoneNotifications(bundleIdentifier: nil) == nil)
    }

    @Test
    func `records are one per worktree and kind`() {
        let done = PhoneNotifications.recordName(.done, path: "/repo/branch")
        #expect(done == PhoneNotifications.recordName(.done, path: "/repo/branch"))
        #expect(done != PhoneNotifications.recordName(.blocked, path: "/repo/branch"))
        #expect(done != PhoneNotifications.recordName(.done, path: "/repo/other"))
        #expect(done.hasPrefix("done-"))
        #expect(done.count == "done-".count + 64)
    }

    @Test
    func `each kind has its own subscription and published key`() {
        let subscriptions = PhoneNotificationKind.allCases.map(PhoneNotifications.subscriptionID)
        #expect(subscriptions == ["agent-done", "agent-blocked"])
        #expect(PhoneNotificationKind.allCases.map(\.defaultsKey) == ["phone-notify-done", "phone-notify-blocked"])
    }
}
