import CoreGraphics
import SanductorCloud
import SanductorData
import TerminalUI

// MARK: - PhoneAlerts

/// The Mac's half of the iPhone alerts: whether this build can send,
/// whether its user is away and the send itself.
public enum PhoneAlerts {
    // MARK: Public

    /// Why Settings cannot offer the toggles, nil when it can.
    public static func unavailableReason() async -> String? {
        guard let cloud else {
            return "This build is not signed for iCloud. "
                + "Run script/install with your team in Signing.xcconfig to send alerts to an iPhone."
        }

        return await cloud.accountIsAvailable() ? nil
            : "Sign this Mac into iCloud with the account your iPhone uses."
    }

    /// Sends a sample of an event at once, away or not, so Settings
    /// can prove the whole path to the phone. Its empty path names no
    /// worktree, so tapping it only opens the app.
    public static func sendTest(_ event: NotificationPreferences.Event, title: String) async throws {
        try await cloud?.send(
            event.phoneKind,
            title: title,
            body: "A test from this Mac's Settings.",
            target: PhoneNotificationTarget(path: "", session: herdrSession),
        )
    }

    // MARK: Internal

    /// Whether the phone should expect this event, published for it.
    static func sends(_ event: NotificationPreferences.Event) -> Bool {
        cloud != nil && NotificationPreferences.sendsToPhone(event)
    }

    /// Sends an alert the Mac is raising anyway, only while nobody is
    /// at the Mac to see it.
    static func send(_ event: NotificationPreferences.Event, title: String, body: String, path: String) {
        guard let cloud, NotificationPreferences.sendsToPhone(event), isAway else {
            return
        }

        let target = PhoneNotificationTarget(path: path, session: herdrSession)
        Task {
            await deliver(event.phoneKind, title: title, body: body, target: target, through: cloud)
        }
    }

    // MARK: Private

    private static let cloud: PhoneNotifications? = .init()

    /// Idle this long counts as away from the Mac.
    private static let idleSeconds: CFTimeInterval = 300

    private static var herdrSession: String {
        if WorkspacePaths.isProductionBuild {
            "sanductor"
        } else {
            "sanductor-dev"
        }
    }

    /// Locked, display asleep or idle, read when an alert fires so
    /// nothing has to watch for it.
    private static var isAway: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        return session?["CGSSessionScreenIsLocked"] as? Bool == true
            || CGDisplayIsAsleep(CGMainDisplayID()) != 0
            || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= idleSeconds
    }

    private static func deliver(
        _ kind: PhoneNotificationKind,
        title: String,
        body: String,
        target: PhoneNotificationTarget,
        through cloud: PhoneNotifications,
    ) async {
        _ = await ErrorLog.shared.attemptingTwice("Could not send an alert to iPhone") {
            try await cloud.send(kind, title: title, body: body, target: target)
        }
    }
}

// MARK: - NotificationPreferences.Event

extension NotificationPreferences.Event {
    /// The kind the phone receives this event as.
    var phoneKind: PhoneNotificationKind {
        if self == .done {
            .done
        } else {
            .blocked
        }
    }
}
