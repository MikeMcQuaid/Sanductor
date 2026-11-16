import Foundation

/// Which agent events notify, chime and count in the Dock badge,
/// set in the Settings window. Every toggle defaults on; the
/// completed turn and input request have their own sounds.
public enum NotificationPreferences {
    // MARK: Public

    /// One notifiable agent event.
    public enum Event: CaseIterable, Sendable {
        case done
        case blocked

        // MARK: Public

        /// The notify toggle's storage key; done and blocked keep
        /// the keys the earlier three-event settings wrote, so an
        /// existing choice holds.
        public var enabledKey: String {
            switch self {
            case .done:
                "notifyFinished"

            case .blocked:
                "notifyNeedsInput"
            }
        }

        /// The Send to iPhone toggle's storage key; off until chosen.
        public var phoneKey: String {
            switch self {
            case .done:
                "sendFinishedToPhone"

            case .blocked:
                "sendNeedsInputToPhone"
            }
        }

        /// The sound path's storage key. The completed turn keeps
        /// the key the original picker wrote.
        public var soundKey: String {
            switch self {
            case .done:
                CompletionSound.key

            case .blocked:
                "needsInputSound"
            }
        }

        /// The sound played when none was chosen: the chime the
        /// completed turn always had and a ping for input requests.
        public var defaultSound: String {
            switch self {
            case .done:
                CompletionSound.defaultPath

            case .blocked:
                "/System/Library/Sounds/Ping.aiff"
            }
        }
    }

    /// The Dock badge toggle's storage key.
    public static let badgeKey = "badgeNeedsInput"

    /// Whether agents waiting for input count in the Dock badge.
    public static var badges: Bool {
        boolDefaultingTrue(badgeKey)
    }

    /// Whether an event posts at all; absent means on.
    public static func notifies(_ event: Event) -> Bool {
        boolDefaultingTrue(event.enabledKey)
    }

    /// Whether the event also goes to the iPhone while its user is
    /// away; absent means off.
    public static func sendsToPhone(_ event: Event) -> Bool {
        UserDefaults.standard.bool(forKey: event.phoneKey)
    }

    /// The event's chosen sound path; the empty string is silence.
    public static func sound(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.soundKey) ?? event.defaultSound
    }

    // MARK: Private

    private static func boolDefaultingTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }
}
