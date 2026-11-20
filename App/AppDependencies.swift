import DashboardFeature
import ReviewFeature
import SanductorData
import SanductorDomain
import SanductorInterface
import TerminalUI

/// Builds every adapter once and hands them to the features; the
/// app's only wiring.
@MainActor
final class AppDependencies {
    // MARK: Lifecycle

    init() throws {
        let paths = WorkspacePaths.current()
        let metadataStore = MetadataStore(file: paths.metadataFile)
        try PortableSettings.backfill()
        settings = try PortableSettings()
        try settings.restorePrompts(in: metadataStore)
        let runner = FoundationProcessRunner()
        let gitClient = GitClient(runner: runner)
        let githubClient = GitHubClient(runner: runner)
        metadataStore.resumeFeedbackLoops()
        let launchProgress = LaunchProgress()
        let herdr = HerdrClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: paths.hostUser),
            isInsideSandbox: WorkspacePaths.isInsideSandbox,
            progress: launchProgress.reporter,
        )
        let sessionService = SessionService(
            paths: paths,
            git: gitClient,
            herdr: herdr,
            github: githubClient,
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: metadataStore,
            runners: [ClaudeCodeRunner(), CodexRunner()],
            progress: launchProgress.reporter,
        )
        git = gitClient
        github = githubClient
        service = sessionService
        agentQuota = AgentQuotaModel(read: sessionService.quota)
        setup = SetupModel(check: SetupChecker(service: sessionService).check)
        localReviews = LocalReviewStore(service: sessionService)
        store = metadataStore
        dashboard = DashboardModel(
            service: sessionService,
            store: metadataStore,
            github: githubClient,
            launchProgress: launchProgress,
        )
        prompts = dashboard.prompts
        prompts.portableSettings = settings
        settings.privateSettingsChanged = { [weak prompts] in prompts?.syncPrivateSettings() }
        prompts.syncPrivateSettings()
        // The machine's own power state, wired here rather than read
        // by the model, so the model under test is always plugged in.
        dashboard.isOnBattery = { PowerSource.isOnBattery }
        Self.shared = self
    }

    deinit {
        // Lives for the app's whole lifetime.
    }

    // MARK: Internal

    /// The one instance, for the App Intents, which the system
    /// invokes outside any view: nil only before the app has built
    /// itself.
    private(set) static var shared: AppDependencies?

    /// Watches whether the machine has a route out at all, so
    /// GitHub work waits rather than failing per branch per poll.
    /// The shared one, which every network call in the app reads.
    let network: NetworkMonitor = .shared

    let git: GitClient
    let github: GitHubClient
    let service: SessionService
    let agentQuota: AgentQuotaModel
    let setup: SetupModel
    let localReviews: LocalReviewStore
    let dashboard: DashboardModel
    let prompts: PromptsModel
    let store: MetadataStore

    let settings: PortableSettings

    func saveSettings() {
        do {
            try settings.saveChanges()
            lastSettingsError = nil
        } catch {
            let message = "Saving settings.plist: " + error.localizedDescription
            guard message != lastSettingsError else {
                return
            }

            lastSettingsError = message
            PerformanceLog.recordMessage(message, isError: true)
            Task {
                await Task.yield()
                guard lastSettingsError == message else {
                    return
                }

                do {
                    try settings.saveChanges()
                    lastSettingsError = nil
                } catch {
                    ErrorLog.shared.report(message + ". Retrying failed: " + error.localizedDescription)
                }
            }
        }
    }

    // MARK: Private

    private var lastSettingsError: String?
}
