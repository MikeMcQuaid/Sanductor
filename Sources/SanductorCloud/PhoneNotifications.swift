import CloudKit
import CryptoKit
import Foundation

// MARK: - PhoneNotificationKind

// SwiftFormat drops raw values that repeat the case name.
// swiftlint:disable explicit_enum_raw_value

/// The Mac's alerts that can also reach the iPhone, by the event
/// that raised them.
public enum PhoneNotificationKind: String, CaseIterable, Sendable {
    case done
    case blocked

    // MARK: Public

    /// The `session-defaults` key telling the phone whether the Mac
    /// sends this kind.
    public var defaultsKey: String {
        "phone-notify-" + rawValue
    }
}

// swiftlint:enable explicit_enum_raw_value

// MARK: - PhoneNotificationTarget

/// The worktree an alert is about, which tapping it opens.
public struct PhoneNotificationTarget: Equatable, Sendable {
    // MARK: Lifecycle

    public init(path: String, session: String) {
        self.path = path
        self.session = session
    }

    // MARK: Public

    public let path: String

    /// The herdr session the sending app uses, `sanductor` or
    /// `sanductor-dev`.
    public let session: String
}

// MARK: - PhoneNotifications

/// The Mac's alerts relayed to the iPhone through the user's own
/// private CloudKit database: the Mac saves one record per worktree
/// and kind, and the phone's query subscriptions turn every save into
/// an alert. Nothing of the project's own runs in between.
public struct PhoneNotifications: Sendable {
    // MARK: Lifecycle

    /// Nil when this build cannot reach iCloud. `CKContainer` traps
    /// without its entitlement, which the Mac's ad hoc builds lack, so
    /// the Mac reads its own signature first; the iPhone target always
    /// carries it.
    public init?(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard let entitled = SanductorContainer(bundleIdentifier: bundleIdentifier) else {
            return nil
        }

        cloud = entitled
    }

    // MARK: Public

    /// The record a tapped alert was raised for, nil for any other
    /// notification.
    public static func recordID(of userInfo: [AnyHashable: Any]) -> CKRecord.ID? {
        (CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification)?.recordID
    }

    /// Whether an iCloud account is signed in, so Settings can say
    /// why nothing would arrive.
    public func accountIsAvailable() async -> Bool {
        await (try? cloud.container.accountStatus()) == .available
    }

    /// The worktree an alert's record names, read from iCloud rather
    /// than the alert, whose copy of a long path may be cut short.
    public func target(of recordID: CKRecord.ID) async throws -> PhoneNotificationTarget? {
        let record = try await cloud.container.privateCloudDatabase.record(for: recordID)
        guard let path = record["path"] as? String, let session = record["session"] as? String else {
            return nil
        }

        return PhoneNotificationTarget(path: path, session: session)
    }

    /// Saves this kind's record for the worktree, replacing any
    /// earlier one without reading it first; the phone's
    /// subscriptions fire on both.
    public func send(
        _ kind: PhoneNotificationKind, title: String, body: String, target: PhoneNotificationTarget,
    ) async throws {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: Self.recordName(kind, path: target.path)),
        )
        record["kind"] = kind.rawValue
        record["title"] = title
        record["body"] = body
        record["path"] = target.path
        record["session"] = target.session
        let (saved, _) = try await cloud.container.privateCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys,
        )
        for result in saved.values {
            _ = try result.get()
        }
    }

    /// Keeps exactly the wanted kinds' subscriptions. Wanted ones are
    /// saved every time, so a changed alert format replaces the old.
    public func subscribe(to kinds: Set<PhoneNotificationKind>) async throws {
        let database = cloud.container.privateCloudDatabase
        let existing = try await Set(database.allSubscriptions().map(\.subscriptionID))
        let unwanted = PhoneNotificationKind.allCases
            .filter { kinds.contains($0) == false }
            .map(Self.subscriptionID)
            .filter(existing.contains)
        let wanted = PhoneNotificationKind.allCases.filter(kinds.contains).map(Self.subscription)
        guard wanted.isEmpty == false || unwanted.isEmpty == false else {
            return
        }

        let (saved, deleted) = try await database.modifySubscriptions(saving: wanted, deleting: unwanted)
        for result in saved.values {
            _ = try result.get()
        }
        for result in deleted.values {
            try result.get()
        }
    }

    // MARK: Internal

    static let recordType = "AgentNotification"

    /// One record per worktree and kind keeps the database bounded.
    static func recordName(_ kind: PhoneNotificationKind, path: String) -> String {
        kind.rawValue + "-" + SHA256.hash(data: Data(path.utf8)).map { unsafe String(format: "%02x", $0) }.joined()
    }

    static func subscriptionID(_ kind: PhoneNotificationKind) -> String {
        "agent-" + kind.rawValue
    }

    // MARK: Private

    private let cloud: SanductorContainer

    private static func subscription(_ kind: PhoneNotificationKind) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(format: "kind == %@", kind.rawValue),
            subscriptionID: subscriptionID(kind),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate],
        )
        let information = CKSubscription.NotificationInfo()
        // A key missing from the app's strings is its own format, so
        // the record's fields become the alert as they are.
        information.titleLocalizationKey = "%1$@"
        information.titleLocalizationArgs = ["title"]
        information.alertLocalizationKey = "%1$@"
        information.alertLocalizationArgs = ["body"]
        information.soundName = "default"
        subscription.notificationInfo = information
        return subscription
    }
}
