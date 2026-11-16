#if os(iOS)
    import MobileFeature
    import SwiftUI
    import UserNotifications

    @main
    struct SanductorApp: App {
        // MARK: Lifecycle

        /// The notification delegate is set before launch finishes,
        /// so tapping an alert that launched the app still opens it.
        init() {
            let mobileModel = MobileModel()
            _model = State(initialValue: mobileModel)
            notificationDelegate = MobileNotificationDelegate(model: mobileModel)
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }

        // MARK: Internal

        var body: some Scene {
            WindowGroup {
                MobileRootView(model: model)
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        if phase == .active {
                            model.activate()
                        } else if phase == .background {
                            model.suspend()
                        }
                    }
            }
        }

        // MARK: Private

        @Environment(\.scenePhase)
        private var scenePhase
        @State private var model: MobileModel

        private let notificationDelegate: MobileNotificationDelegate
    }
#endif
