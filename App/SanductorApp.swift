import AppKit
import DashboardFeature
import SanductorData
import SanductorInterface
import SwiftUI
import TerminalUI

// MARK: - AppDelegate

/// Quits the app when its last window closes. Everything that must
/// survive lives outside the process: herdr sessions and their
/// agents keep running, and the event spool holds notifications for
/// the next launch. A windowless Sanductor polled nothing and
/// delivered nothing, so staying resident was a dead app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Lifecycle

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Internal

    let launch: ApplicationLaunch = .init()

    func applicationDidFinishLaunching(_: Notification) {
        launch.didFinishLaunching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

// MARK: - SanductorApp

@main
struct SanductorApp: App {
    // MARK: Lifecycle

    init() {
        // A single-window app: disabling window tabs also removes the
        // stock Show Tab Bar and Show All Tabs items from View.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Every field here holds code, a commit message or a pull
        // request body, and text substitution turns quotes into
        // curly ones and double dashes into em dashes in all of
        // them. The app's own defaults turn it off for the SwiftUI
        // fields, whose text views it cannot otherwise reach; the
        // code editor sets the same switches on itself.
        for key in [
            "NSAutomaticQuoteSubstitutionEnabled",
            "NSAutomaticDashSubstitutionEnabled",
            "NSAutomaticTextReplacementEnabled",
            "NSAutomaticSpellingCorrectionEnabled",
            "NSAutomaticCapitalizationEnabled",
            "NSAutomaticPeriodSubstitutionEnabled",
        ] {
            UserDefaults.standard.set(false, forKey: key)
        }
        if LegacyMigration.isNeeded() == false, LegacyMigration.isSandboxMigrationNeeded() == false {
            _dependencies = State(initialValue: AppDependencies())
        }
    }

    // MARK: Internal

    /// Installs `AppDelegate`, which quits the app when its last
    /// window closes. Internal, not private: nothing references it,
    /// so the formatter's unused-private-declaration rule silently
    /// deleted a private one, and the delegate with it.
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var delegate

    var body: some Scene {
        // Register before any scene exists; scene builders need a declaration here.
        // swiftlint:disable:next redundant_discardable_let
        let _ = delegate.launch.whenReady {
            Task {
                await launch()
            }
        }
        WindowGroup(id: "workspace") {
            Group {
                if let dependencies {
                    if dependencies.setup.isReady {
                        RootView(dependencies: dependencies)
                            .onChange(of: dependencies.setup.agents, initial: true) {
                                if dependencies.setup.agents.isEmpty == false {
                                    dependencies.dashboard.availableAgents = dependencies.setup.agents
                                }
                            }
                    } else if dependencies.setup.currentIssue != nil {
                        SetupView(model: dependencies.setup)
                    } else {
                        opening
                    }
                } else {
                    opening
                }
            }
            .environment(\.openURL, LinkOpener.action)
            .interfaceFont(.body)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        // Content over chrome: no title bar, compact toolbar.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            if let dependencies {
                AppCommands(dashboard: dependencies.dashboard, isReady: dependencies.setup.isReady)
            }
        }

        Settings {
            Group {
                if let dependencies {
                    if dependencies.setup.isReady {
                        SettingsView(dependencies: dependencies)
                    } else if dependencies.setup.currentIssue != nil {
                        SetupView(model: dependencies.setup)
                    } else {
                        opening
                    }
                } else {
                    opening
                }
            }
            .interfaceFont(.body)
            .task { await prepare() }
        }
    }

    // MARK: Private

    private static let migrationAttempts = 2
    private static let terminationAttempts = 50
    private static let terminationPause: Duration = .milliseconds(100)
    private static let openingDelaySeconds = 0.5

    @Environment(\.openWindow)
    private var openWindow

    @State private var dependencies: AppDependencies?
    @State private var hasOpenedWindow = false
    @State private var isPreparing = false
    @State private var openingError: String?
    @State private var progress: LaunchProgress = .init()

    private var opening: some View {
        VStack {
            if let openingError {
                Text(openingError)
                BusyButton("Retry", busy: "Retrying", prominent: true) { await prepare() }
                    .keyboardShortcut(.defaultAction)
            } else {
                LaunchProgressView("Opening Sanductor", progress: progress)
            }
        }
        .interfaceFont(.body)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func launch() async {
        guard hasOpenedWindow == false, isPreparing == false else {
            return
        }

        if dependencies?.setup.isReady == true {
            showWindow()
        }
        let delayedOpening = Task {
            try? await Task.sleep(for: .seconds(Self.openingDelaySeconds))
            if Task.isCancelled == false {
                showWindow()
            }
        }
        defer { delayedOpening.cancel() }
        await prepare()
        showWindow()
    }

    private func showWindow() {
        guard hasOpenedWindow == false else {
            return
        }

        hasOpenedWindow = true
        openWindow(id: "workspace")
    }

    private func prepare() async {
        guard isPreparing == false else {
            return
        }

        isPreparing = true
        defer { isPreparing = false }
        openingError = nil
        if dependencies == nil {
            for attempt in 0 ..< Self.migrationAttempts {
                do {
                    progress.begin(attempt == 0 ? "Restoring saved work" : "Retrying saved work restoration")
                    let previous = NSRunningApplication.runningApplications(
                        withBundleIdentifier: "com.mikemcquaid.AgentIDE",
                    )
                    for application in previous {
                        application.terminate()
                    }
                    // Process state also covers exits before a termination notification can be observed.
                    for _ in 0 ..< Self.terminationAttempts where previous.allSatisfy(\.isTerminated) == false {
                        try await Task.sleep(for: Self.terminationPause)
                    }
                    guard previous.allSatisfy(\.isTerminated) else {
                        throw NSError(
                            domain: "SanductorMigration",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "AgentIDE is still closing. Close it, then retry."],
                        )
                    }

                    progress.report("Restoring settings and conversations")
                    try await Task.detached(priority: .userInitiated) {
                        try LegacyMigration.run()
                    }.value
                    progress.report("Restoring agent sessions")
                    try await LegacyMigration.prepareSandbox(paths: .current())
                    try Task.checkCancellation()
                    dependencies = AppDependencies()
                    break
                } catch is CancellationError {
                    return
                } catch {
                    if attempt == Self.migrationAttempts - 1 {
                        openingError = error.localizedDescription
                    }
                }
            }
        }
        await dependencies?.setup.checkOnLaunch()
    }
}
