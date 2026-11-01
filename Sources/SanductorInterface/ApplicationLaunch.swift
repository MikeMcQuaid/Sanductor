/// Starts once both AppKit and the app's scene-opening action are ready.
public final class ApplicationLaunch {
    // MARK: Lifecycle

    /// Waits without creating a window or constructing setup views.
    public init() { /* Readiness arrives independently from the app and its delegate. */ }

    deinit { /* The callback is released when launch starts. */ }

    // MARK: Public

    /// Registers the action even when the workspace scene is suppressed.
    public func whenReady(_ action: @escaping () -> Void) {
        guard hasStarted == false else {
            return
        }

        self.action = action
        startIfReady()
    }

    /// Called by the application delegate, independently of scene visibility.
    public func didFinishLaunching() {
        applicationReady = true
        startIfReady()
    }

    // MARK: Private

    private var applicationReady = false
    private var hasStarted = false
    private var action: (() -> Void)?

    private func startIfReady() {
        guard applicationReady, hasStarted == false, let action else {
            return
        }

        hasStarted = true
        self.action = nil
        action()
    }
}
