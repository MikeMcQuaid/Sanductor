import Foundation
@testable import MobileFeature
import SanductorCloud
import SanductorRemote
import Testing

struct MobileNotificationTests {
    // MARK: Internal

    @Test
    func `nothing changes until the Mac's choices have been read`() throws {
        let preferences = try #require(UserDefaults(suiteName: #function))
        defer { preferences.removePersistentDomain(forName: #function) }
        #expect(MobileModel.wantedNotifications(macDefaults: [:], preferences: preferences) == nil)
        #expect(MobileModel.wantedNotifications(
            macDefaults: ["phone-notify-done": "1"], preferences: preferences,
        ) == nil)
    }

    @Test
    func `the phone receives what the Mac sends unless turned off here`() throws {
        let preferences = try #require(UserDefaults(suiteName: #function))
        defer { preferences.removePersistentDomain(forName: #function) }
        let both = ["phone-notify-done": "1", "phone-notify-blocked": "1"]
        #expect(MobileModel.wantedNotifications(macDefaults: both, preferences: preferences) == [.done, .blocked])
        #expect(MobileModel.wantedNotifications(
            macDefaults: ["phone-notify-done": "0", "phone-notify-blocked": "1"], preferences: preferences,
        ) == [.blocked])
        preferences.set(false, forKey: MobileModel.receiveKey(.blocked))
        #expect(MobileModel.wantedNotifications(macDefaults: both, preferences: preferences) == [.done])
    }

    @Test
    func `a tapped alert selects its worktree once the session list holds it`() {
        let model = MobileModel(configuration: SSHConfiguration())
        let target = PhoneNotificationTarget(path: "/repo/branch", session: model.configuration.session)
        model.open(target)
        #expect(model.selection == nil)
        model.allSessions = [
            Self.session("other", in: "/repo/branch-other"),
            Self.session("pane", in: "/repo/branch/subdirectory"),
        ]
        model.selectNotifiedWorktree()
        #expect(model.selection?.id == "pane")
    }

    @Test
    func `an alert from the other herdr session leaves the selection alone`() {
        let model = MobileModel(configuration: SSHConfiguration())
        model.allSessions = [Self.session("pane", in: "/repo/branch")]
        model.open(PhoneNotificationTarget(path: "/repo/branch", session: "sanductor-dev"))
        #expect(model.selection == nil)
    }

    @Test
    func `a waiting alert selects nothing once Settings switches herdr session`() {
        let model = MobileModel(configuration: SSHConfiguration())
        model.open(PhoneNotificationTarget(path: "/repo/branch", session: model.configuration.session))
        model.configuration.session = "sanductor-dev"
        model.allSessions = [Self.session("pane", in: "/repo/branch")]
        model.selectNotifiedWorktree()
        #expect(model.selection == nil)
    }

    @Test
    func `a test alert names no worktree and leaves the selection alone`() {
        let model = MobileModel(configuration: SSHConfiguration())
        model.allSessions = [Self.session("pane", in: "/repo/branch")]
        model.open(PhoneNotificationTarget(path: "", session: model.configuration.session))
        #expect(model.selection == nil)
    }

    // MARK: Private

    private static func session(_ id: String, in directory: String) -> MobileSession {
        MobileSession(
            id: id,
            name: id,
            repository: "repo",
            branch: id,
            agent: .codexCLI,
            activity: nil,
            directory: directory,
        )
    }
}
