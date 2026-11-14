import SanductorDomain
import SanductorInterface
import SwiftUI

/// One editor for reusable text and its optional repository schedule.
struct PromptEditorSheet: View {
    // MARK: Lifecycle

    init(
        prompt: SavedPrompt,
        model: PromptsModel,
        repositories: [Repository],
        choices: @escaping (AgentKind) -> AgentChoices,
    ) {
        _prompt = State(initialValue: prompt)
        self.model = model
        self.repositories = repositories
        self.choices = choices
    }

    // MARK: Internal

    let model: PromptsModel
    let repositories: [Repository]
    let choices: (AgentKind) -> AgentChoices

    var body: some View {
        VStack {
            Form {
                Section("Prompt") {
                    TextField("Name", text: $prompt.name)
                        .focused($nameFocused)
                    TextField("Prompt", text: $prompt.prompt, axis: .vertical)
                        .lineLimit(Self.promptLines)
                    Toggle("Run on a schedule", isOn: Binding(
                        get: { prompt.schedule != nil },
                        set: { enabled in
                            prompt.schedule = enabled ? PromptSchedule() : nil
                            if enabled, prompt.repositoryPath.isEmpty {
                                prompt.repositoryPath = repositories.first?.path ?? ""
                            }
                        },
                    ))
                }
                if prompt.schedule != nil {
                    sessionSection
                    scheduleSection
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            buttons
        }
        .frame(width: Self.width, height: prompt.schedule == nil ? Self.plainHeight : Self.scheduledHeight)
        .animation(Motion.quick, value: prompt.schedule != nil)
        .onAppear { nameFocused = true }
    }

    // MARK: Private

    private static let width: CGFloat = 620
    private static let avatarSize: CGFloat = 14
    private static let plainHeight: CGFloat = 360
    private static let scheduledHeight: CGFloat = 680
    private static let promptLines = 5 ... 10

    @State private var prompt: SavedPrompt

    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var nameFocused: Bool

    private var recurrence: Binding<PromptSchedule> {
        Binding(get: { prompt.schedule ?? PromptSchedule() }, set: { prompt.schedule = $0 })
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(
                    hour: prompt.schedule?.hour, minute: prompt.schedule?.minute,
                )) ?? Date()
            },
            set: { date in
                prompt.schedule?.hour = Calendar.current.component(.hour, from: date)
                prompt.schedule?.minute = Calendar.current.component(.minute, from: date)
            },
        )
    }

    private var sessionSection: some View {
        Section("Session") {
            Picker("Repository", selection: $prompt.repositoryPath) {
                if prompt.repositoryPath.isEmpty {
                    Text("Choose a repository").tag("")
                }
                ForEach(repositories) { repository in
                    Label { Text(repository.name) } icon: {
                        OwnerAvatar(owner: repository.owner, size: Self.avatarSize).menuImage
                    }
                    .tag(repository.path)
                }
            }
            AgentOptionPickers(
                agent: $prompt.agent, model: $prompt.model, effort: $prompt.effort, choices: choices,
            )
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Repeat", selection: recurrence.frequency) {
                ForEach(PromptSchedule.Frequency.allCases, id: \.self) { frequency in
                    Text(frequency.rawValue.capitalized).tag(frequency)
                }
            }
            if prompt.schedule?.frequency == .weekly {
                Picker("On", selection: recurrence.weekday) {
                    ForEach(PromptSchedule.weekdays, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
            } else if prompt.schedule?.frequency == .monthly {
                Picker("On day", selection: recurrence.day) {
                    ForEach(PromptSchedule.monthDays, id: \.self) { day in
                        Text(String(day)).tag(day)
                    }
                }
                Text("Months without this day are skipped.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
            Text("Time zone: " + (prompt.schedule?.timeZoneIdentifier ?? ""))
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enabled", isOn: $prompt.isEnabled)
            Text("Runs while Sanductor is open. Reopening or waking runs each overdue prompt once.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                if model.save(prompt) {
                    dismiss()
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(prompt.isValid == false || (prompt.schedule != nil
                    && choices(prompt.agent).supports(model: prompt.model, effort: prompt.effort) == false))
        }
        .padding([.horizontal, .bottom])
    }
}
