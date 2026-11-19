import CloudKit
import Foundation
import SanductorCloud
#if os(iOS)
    import UIKit
    import UserNotifications
#endif

extension MobileModel {
    // MARK: Public

    /// Opens the worktree a tapped alert's record names, read whole
    /// from iCloud since the alert's own copy of a long path may be
    /// cut short.
    public func open(alert recordID: CKRecord.ID) {
        open(alert: recordID) { try await PhoneNotifications()?.target(of: $0) }
    }

    // MARK: Internal

    /// Reads an alert's record, retrying while iCloud is briefly
    /// unreachable; a later tap supersedes it, so an earlier read
    /// finishing last cannot select the older worktree.
    @discardableResult
    func open(
        alert recordID: CKRecord.ID,
        lookup: @escaping (CKRecord.ID) async throws -> PhoneNotificationTarget?,
    ) -> Task<Void, Never> {
        alertLookup?.cancel()
        notifiedWorktree = nil
        isOpeningAlert = true
        let task = Task {
            for attempt in 1 ... Self.alertReadAttempts {
                do {
                    let target = try await lookup(recordID)
                    guard Task.isCancelled == false else {
                        return
                    }

                    isOpeningAlert = false
                    if let target {
                        open(target)
                    }
                    return
                } catch let error as CKError where attempt < Self.alertReadAttempts && Self.isTransient(error) {
                    try? await Task.sleep(for: .seconds(error.retryAfterSeconds ?? Double(attempt)))
                    guard Task.isCancelled == false else {
                        return
                    }
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }

                    isOpeningAlert = false
                    notificationError = "Could not open the Mac's alert: " + error.localizedDescription
                    return
                }
            }
        }
        alertLookup = task
        return task
    }

    /// The receive toggle's storage key; absence means on.
    static func receiveKey(_ kind: PhoneNotificationKind) -> String {
        "receive-" + kind.rawValue + "-notifications"
    }

    /// Whether the Mac has said it does not send a kind, read from its
    /// published session choices.
    static func macWithholds(_ kind: PhoneNotificationKind, in macDefaults: [String: String]) -> Bool {
        macDefaults[kind.defaultsKey] == "0"
    }

    /// The kinds the Mac sends and this phone wants; nil until the
    /// Mac's choices have been read, so an unconnected phone changes
    /// nothing.
    static func wantedNotifications(
        macDefaults: [String: String], preferences: UserDefaults = .standard,
    ) -> Set<PhoneNotificationKind>? { // swiftlint:disable:this discouraged_optional_collection
        guard PhoneNotificationKind.allCases.allSatisfy({ macDefaults[$0.defaultsKey] != nil }) else {
            return nil
        }

        return Set(PhoneNotificationKind.allCases.filter { kind in
            macDefaults[kind.defaultsKey] == "1"
                && preferences.object(forKey: Self.receiveKey(kind)) as? Bool ?? true
        })
    }

    /// Brings the iCloud subscriptions in line with what is wanted,
    /// asking for permission once an alert is wanted at all. One
    /// change runs at a time and a superseded one is skipped: an
    /// earlier save finishing after a later delete would leave iCloud
    /// sending what was turned off.
    func updateNotifications() {
        guard let wanted = Self.wantedNotifications(macDefaults: defaults), wanted != subscribedNotifications,
              let cloud = PhoneNotifications()
        else {
            return
        }

        subscribedNotifications = wanted
        notificationUpdate = Task { [previous = notificationUpdate] in
            await previous?.value
            guard subscribedNotifications == wanted else {
                return
            }

            do {
                notificationError = wanted.isEmpty ? nil : await allowAlerts()
                try await cloud.subscribe(to: wanted)
            } catch {
                if subscribedNotifications == wanted {
                    subscribedNotifications = nil
                }
                notificationError = "Could not set up the Mac's alerts: " + error.localizedDescription
            }
        }
    }

    /// Opens the worktree an alert names, now or once the session
    /// list holds it. An alert from another herdr session than the
    /// one now chosen, or a test naming no worktree, selects nothing.
    func open(_ target: PhoneNotificationTarget) {
        guard target.path.isEmpty == false else {
            return
        }

        notifiedWorktree = target
        selectNotifiedWorktree()
    }

    func selectNotifiedWorktree() {
        guard let target = notifiedWorktree, target.session == configuration.session,
              let session = sessions.first(where: { session in
                  session.directory == target.path || session.directory?.hasPrefix(target.path + "/") == true
              })
        else {
            return
        }

        notifiedWorktree = nil
        selection = session
    }

    // MARK: Private

    private static let alertReadAttempts = 3

    private static func isTransient(_ error: CKError) -> Bool {
        [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy]
            .contains(error.code)
    }

    /// Asks to show alerts and registers for the pushes CloudKit
    /// sends, returning what to tell the user when alerts are refused.
    private func allowAlerts() async -> String? {
        #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            let allowed = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            return allowed == true ? nil
                : "Allow notifications for Sanductor in the iPhone's Settings to see the Mac's alerts."
        #else
            nil
        #endif
    }
}
