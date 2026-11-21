import Foundation
import Observation
import SanductorCloud
import SanductorData
import SanductorDomain
import TerminalUI

/// Owns reusable prompts and a single timer for their optional schedules.
@preconcurrency
@Observable
@MainActor
public final class PromptsModel {
    // MARK: Lifecycle

    /// Loads saved prompts without starting any work.
    public init(store: MetadataStore, service: SessionService) {
        self.store = store
        prompts = store.load().savedPrompts
        launch = { try await service.launchScheduledPrompt($0, due: $1) }
    }

    deinit {
        // The timer captures the app-owned model weakly.
    }

    // MARK: Public

    /// The in-memory library shared by Settings and prompt menus.
    public private(set) var prompts: [SavedPrompt]
    /// The Mac app’s file for user-edited prompt text.
    public var portableSettings: PortableSettings?
    /// The schedule whose agent is currently being launched.
    public private(set) var runningID: UUID?
    /// The last persistence failure, also preventing unrecorded launches.
    public private(set) var error: String?

    /// Edits preserve launch results, including a launch that finished
    /// while the editor was open. Schedule configuration changes reset the due date.
    @discardableResult
    public func save(_ draft: SavedPrompt) -> Bool {
        let next = draft.schedule?.nextRun(after: now())
        guard draft.isValid, draft.schedule == nil || next != nil else {
            return false
        }

        var prompt = draft
        if prompt.schedule == nil {
            prompt.repositoryPath = ""
        }
        if let previous = prompts.first(where: { $0.id == draft.id }) {
            prompt.lastRun = previous.lastRun
            prompt.lastSession = previous.lastSession
            prompt.lastError = previous.lastError
            prompt.nextRun = draft.schedule != nil && previous.schedule == draft.schedule
                && previous.repositoryPath == draft.repositoryPath && previous.isEnabled == draft.isEnabled
                ? previous.nextRun : next
        } else {
            prompt.nextRun = next
        }
        return persist { prompts in
            prompts.removeAll { $0.id == prompt.id }
            prompts.append(prompt)
        } portable: {
            try self.portableSettings?.savePrompt(prompt)
        }
    }

    /// Removes future runs while preserving existing sessions.
    public func delete(_ prompt: SavedPrompt) {
        _ = persist { prompts in
            prompts.removeAll { $0.id == prompt.id }
        } portable: {
            try self.portableSettings?.deletePrompt(id: prompt.id)
        }
    }

    /// Runs each overdue schedule once. Claiming before awaiting also
    /// coalesces wake, timer and clock-change requests during a launch.
    public func runDue() async {
        guard runningID == nil else {
            return
        }

        timer?.invalidate()
        defer { armTimer() }
        let dueIDs = prompts.filter { prompt in
            prompt.schedule != nil && prompt.isEnabled && (prompt.nextRun ?? .distantFuture) <= now()
        }
        .map(\.id)
        for id in dueIDs {
            guard let prompt = prompts.first(where: { $0.id == id }), prompt.isEnabled, prompt.schedule != nil,
                  let due = prompt.nextRun, due <= now()
            else {
                continue
            }

            if isOnWorkHoliday(prompt) {
                _ = persist { prompts in
                    if let index = prompts.firstIndex(where: { $0.id == id }) {
                        prompts[index].nextRun = prompt.schedule?.nextRun(after: now())
                    }
                }
            } else {
                await run(prompt, due: due, advancesSchedule: true)
            }
            if error != nil {
                return
            }
        }
    }

    /// Starts the latest saved job without moving a future occurrence or unpausing it.
    public func start(_ savedPrompt: SavedPrompt) async {
        guard runningID == nil, let prompt = prompts.first(where: { $0.id == savedPrompt.id }), prompt.isValid,
              prompt.schedule != nil, isOnWorkHoliday(prompt) == false
        else {
            return
        }

        let due = max(now(), (prompt.lastRun ?? .distantPast).addingTimeInterval(1))
        await run(
            prompt,
            due: due,
            advancesSchedule: prompt.isEnabled && (prompt.nextRun ?? .distantFuture) <= now(),
        )
    }

    // MARK: Internal

    var cloudStatus = "Private settings are saved on this Mac."
    let cloud: PrivateSettingsCloud? = PrivateSettingsCloud()
    @ObservationIgnored var cloudSyncRequested = false
    @ObservationIgnored var cloudTask: Task<Void, Never>?

    var now: () -> Date = Date.init
    var workMode: () -> WorkMode = { AppSettings.workMode }
    var launch: (SavedPrompt, Date) async throws -> String

    let store: MetadataStore

    func reloadPrompts() {
        let saved = store.load().savedPrompts
        if prompts != saved {
            prompts = saved
            armTimer()
        }
    }

    func availablePrompts(repositoryPath: String?) -> [SavedPrompt] {
        prompts.filter { $0.isValid && ($0.schedule == nil || $0.repositoryPath == repositoryPath) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isOnWorkHoliday(_ prompt: SavedPrompt) -> Bool {
        let settings = workMode()
        guard settings.isOnHoliday(at: now()),
              let repository = store.load().cachedSidebar.first(where: { $0.path == prompt.repositoryPath })
        else {
            return false
        }

        return settings.includes(Repository(
            name: repository.name, path: repository.path, fullName: repository.fullName,
        ))
    }

    // MARK: Private

    private static let saveAttempts = 2

    private var timer: Timer?

    private func run(_ prompt: SavedPrompt, due: Date, advancesSchedule: Bool) async {
        runningID = prompt.id
        timer?.invalidate()
        defer { runningID = nil; armTimer() }
        guard persist({ prompts in
            guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
                return
            }

            if advancesSchedule {
                prompts[index].nextRun = prompt.schedule?.nextRun(after: now())
            }
            prompts[index].lastRun = max(now(), due)
            prompts[index].lastSession = nil
            prompts[index].lastError = "Launch interrupted before its result was recorded."
        }) else {
            return
        }

        var session: String?
        var failure: String?
        _ = await ErrorLog.shared.attemptingTwice("Scheduled prompt “" + prompt.name + "”") {
            do {
                session = try await self.launch(prompt, due)
                failure = nil
            } catch {
                failure = error.localizedDescription
                throw error
            }
        }
        _ = persist { prompts in
            guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
                return
            }

            prompts[index].lastSession = session
            prompts[index].lastError = failure
        }
        UtilityTabTarget.requestSidebarRefresh()
    }

    private func persist(_ change: (inout [SavedPrompt]) -> Void, portable: (() throws -> Void)? = nil) -> Bool {
        var firstFailure: String?
        for _ in 0 ..< Self.saveAttempts {
            do {
                let previous = store.load().savedPrompts
                try store.updatePersisting { change(&$0.savedPrompts) }
                do {
                    try portable?()
                } catch {
                    try store.updatePersisting { $0.savedPrompts = previous }
                    throw error
                }
                prompts = store.load().savedPrompts
                error = nil
                armTimer()
                return true
            } catch {
                if let firstFailure {
                    self.error = "Could not save prompts: " + firstFailure
                        + "; then again: " + error.localizedDescription
                } else {
                    firstFailure = error.localizedDescription
                    PerformanceLog.recordMessage("Saving prompts: " + error.localizedDescription, isError: true)
                }
            }
        }
        if let error {
            ErrorLog.shared.report(error)
        }
        return false
    }

    private func armTimer() {
        timer?.invalidate()
        timer = nil
        guard runningID == nil, error == nil,
              let next = prompts.filter({ $0.schedule != nil && $0.isEnabled }).compactMap(\.nextRun).min()
        else {
            return
        }

        let alarm = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.runDue()
            }
        }
        timer = alarm
        RunLoop.main.add(alarm, forMode: .common)
    }
}
