import SanductorDomain
import SanductorInterface
import SwiftUI

/// The prompt library, including repository schedules, in Settings.
public struct PromptsView: View {
    // MARK: Lifecycle

    public init(model: PromptsModel, dashboard: DashboardModel) {
        self.model = model
        self.dashboard = dashboard
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading) {
            header
            Text(model.cloudStatus)
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(repositoryPrompts) { prompt in
                        row(prompt)
                        Divider()
                    }
                }
            }
            .overlay {
                if repositoryPrompts.isEmpty {
                    ContentUnavailableView(
                        "No saved prompts",
                        systemImage: "text.bubble",
                        description: Text("Add reusable text and optionally configure a schedule."),
                    )
                }
            }
        }
        .padding()
        .frame(minHeight: Self.height)
        .task(id: repositories.compactMap(\.owner)) { OwnerAvatar.preload(repositories.compactMap(\.owner)) }
        .sheet(item: $editing) { prompt in
            PromptEditorSheet(
                prompt: prompt, model: model, repositories: repositories, choices: dashboard.launchChoices,
            )
        }
    }

    // MARK: Private

    private static let previewLines = 2
    private static let height: CGFloat = 480
    private static let avatarSize: CGFloat = 14

    @State private var repositoryPath = ""
    @State private var editing: SavedPrompt?

    private let model: PromptsModel
    private let dashboard: DashboardModel

    private var repositories: [Repository] {
        Set(dashboard.groups.map(\.repository.path) + model.prompts.map(\.repositoryPath) + [repositoryPath])
            .filter { $0.isEmpty == false }
            .sorted()
            .map { path in
                dashboard.groups.first { $0.repository.path == path }?.repository
                    ?? Repository(name: URL(filePath: path).lastPathComponent, path: path)
            }
    }

    private var repositoryPrompts: [SavedPrompt] {
        model.prompts
            .filter { repositoryPath.isEmpty || $0.schedule == nil || $0.repositoryPath == repositoryPath }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var header: some View {
        HStack {
            Picker("Repository", selection: $repositoryPath) {
                Text("All repositories").tag("")
                ForEach(repositories) { repository in
                    Label { Text(repository.name) } icon: {
                        OwnerAvatar(owner: repository.owner, size: Self.avatarSize).menuImage
                    }
                    .tag(repository.path)
                }
            }
            Spacer()
            Button("Add prompt", systemImage: "plus") {
                var prompt = SavedPrompt()
                prompt.repositoryPath = repositoryPath
                prompt.agent = AgentKind(rawValue: UserDefaults.standard.string(forKey: "agentKind") ?? "")
                    ?? .claudeCode
                editing = prompt
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .hoverHelp("Add a reusable prompt with an optional schedule")
        }
    }

    private func row(_ prompt: SavedPrompt) -> some View {
        HStack {
            details(prompt)
            Spacer()
            controls(prompt)
        }
        .padding(.vertical)
        .disabled(model.runningID == prompt.id)
    }

    private func controls(_ prompt: SavedPrompt) -> some View {
        VStack(alignment: .trailing) {
            HStack {
                Button("Edit prompt", systemImage: "pencil") { editing = prompt }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .hoverHelp("Edit this prompt and its optional schedule")
                Button("Delete prompt", systemImage: "trash", role: .destructive) { model.delete(prompt) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .hoverHelp("Remove this prompt; existing sessions and worktrees are kept")
            }
            if prompt.schedule != nil {
                HStack {
                    Toggle("Enable “" + prompt.name + "”", isOn: Binding(
                        get: { prompt.isEnabled },
                        set: { enabled in
                            var updated = prompt
                            updated.isEnabled = enabled
                            model.save(updated)
                        },
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    startButton(prompt)
                }
            }
        }
        .fixedSize()
    }

    private func details(_ prompt: SavedPrompt) -> some View {
        VStack(alignment: .leading) {
            SavedPromptLabel(
                prompt: prompt, owner: repositories.first { $0.path == prompt.repositoryPath }?.owner,
            )
            .interfaceFont(.headline)
            Text(prompt.prompt)
                .lineLimit(Self.previewLines)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let schedule = prompt.schedule {
                let summary = scheduleSummary(prompt, schedule: schedule)
                HStack {
                    OwnerAvatar(
                        owner: repositories.first { $0.path == prompt.repositoryPath }?.owner, size: Self.avatarSize,
                    )
                    Text(summary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .interfaceFont(.caption)
                .hoverHelp(summary + (prompt.lastSession.map { "\n" + $0 } ?? ""))
                if model.runningID == prompt.id {
                    Label("Starting agent…", systemImage: "hourglass")
                } else if let error = prompt.lastError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
    }

    private func startButton(_ prompt: SavedPrompt) -> some View {
        BusyButton(
            "",
            busy: "",
            systemImage: "play.fill",
            accessibilityLabel: "Start prompt",
            disabled: model.runningID != nil || prompt.isValid == false || model.isOnWorkHoliday(prompt),
        ) {
            await model.start(prompt)
        }
        .hoverHelp(model.isOnWorkHoliday(prompt)
            ? "Work schedules are paused during holiday mode"
            : "Start this prompt now without changing its future schedule")
    }

    private func scheduleSummary(_ prompt: SavedPrompt, schedule: PromptSchedule) -> String {
        var parts = [
            URL(filePath: prompt.repositoryPath).lastPathComponent,
            schedule.frequency.rawValue.capitalized, prompt.agent.displayName,
        ]
        if let last = prompt.lastRun {
            parts.append("Last: " + last.formatted(date: .abbreviated, time: .shortened))
        }
        if prompt.isEnabled, let next = prompt.nextRun {
            parts.append("Next: " + next.formatted(date: .abbreviated, time: .shortened))
        } else {
            parts.append("Paused")
        }
        return parts.joined(separator: " · ")
    }
}
