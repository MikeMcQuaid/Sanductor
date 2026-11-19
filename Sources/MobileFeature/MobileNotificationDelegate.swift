#if os(iOS)
    import SanductorCloud
    import UserNotifications

    /// Shows the Mac's alerts while the app is in front and opens the
    /// worktree a tapped one names.
    public final class MobileNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        // MARK: Lifecycle

        public init(model: MobileModel) {
            self.model = model
        }

        deinit { /* The model outlives the delegate. */ }

        // MARK: Public

        /// The completion handler forms: the async ones have no await,
        /// which SwiftFormat strips, and the protocol then rejects them.
        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void,
        ) {
            completionHandler([.banner, .list, .sound])
        }

        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: () -> Void,
        ) {
            if let recordID = PhoneNotifications.recordID(of: response.notification.request.content.userInfo) {
                model.open(alert: recordID)
            }
            completionHandler()
        }

        // MARK: Private

        private let model: MobileModel
    }
#endif
