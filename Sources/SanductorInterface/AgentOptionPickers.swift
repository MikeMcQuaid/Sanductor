import SanductorDomain
import SwiftUI

/// The agent, model and effort dropdowns shared by every session
/// creation surface. Each opens on something: the last pick where it
/// still exists, and what the agent itself would run otherwise, so
/// changing agent leaves a model and an effort chosen rather than two
/// empty pickers and a form that will not start.
public struct AgentOptionPickers: View {
    // MARK: Lifecycle

    /// Creates the pickers; public so the Settings window can offer
    /// the same controls the session forms use.
    public init(
        agent: Binding<AgentKind>,
        model: Binding<String>,
        effort: Binding<String>,
        choices: @escaping (AgentKind) -> AgentChoices,
        showsAgent: Bool = true,
    ) {
        _agent = agent
        _model = model
        _effort = effort
        self.choices = choices
        self.showsAgent = showsAgent
    }

    // MARK: Public

    public var body: some View {
        Group {
            #if os(iOS)
                pickers
            #else
                HStack(spacing: Self.spacing) { pickers }.labelsHidden()
            #endif
        }
        // On appearance as well as on change: the agent, model and
        // effort all persist across launches now, but discovery can
        // change what a CLI offers between runs, and a persisted pair
        // must never combine a model one agent knows with another.
        .onAppear { resetUnavailableChoices() }
        .onChange(of: agent) { resetUnavailableChoices() }
        .onChange(of: model) { resetUnavailableChoices() }
        .onChange(of: choices(agent)) { resetUnavailableChoices() }
    }

    // MARK: Internal

    let choices: (AgentKind) -> AgentChoices
    let showsAgent: Bool

    func agentIcon(_ image: Image) -> some View {
        #if os(iOS)
            // Native picker labels need the image itself sized, including its trailing space.
            Image(size: CGSize(
                width: mobileAgentIconSize + Self.spacing, height: mobileAgentIconSize,
            )) { context in
                context.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: mobileAgentIconSize, height: mobileAgentIconSize),
                )
            }
            .accessibilityHidden(true)
        #else
            image
                .resizable()
                .scaledToFit()
                .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
        #endif
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let agentIconSize: CGFloat = 8

    @Binding private var agent: AgentKind
    @Binding private var model: String
    @Binding private var effort: String

    #if os(iOS)
        @ScaledMetric(relativeTo: .body)
        private var mobileAgentIconSize = 14.0
    #endif

    @ViewBuilder private var pickers: some View {
        if showsAgent {
            agentPicker
        }
        Picker("Model", selection: $model) {
            ForEach(choices(agent).models, id: \.self) { name in
                Text(AgentOptionName.display(name, named: choices(agent).names)).tag(name)
            }
        }
        .hoverHelp("The model the agent uses")
        .disabled(choices(agent).models.isEmpty)
        if choices(agent).models.isEmpty {
            Text(agent.displayName + "'s default model")
                .foregroundStyle(.secondary)
                .hoverHelp("Model discovery has not answered, so the agent starts on the model its CLI chooses")
        }
        if choices(agent).supportedEfforts(for: model).isEmpty == false {
            Picker("Effort", selection: $effort) {
                ForEach(choices(agent).supportedEfforts(for: model), id: \.self) { name in
                    Text(AgentOptionName.display(name, named: choices(agent).names)).tag(name)
                }
            }
            .hoverHelp("How much reasoning the agent spends")
        }
    }

    private var agentPicker: some View {
        Picker("Agent", selection: $agent) {
            ForEach(AgentKind.allCases, id: \.self) { kind in
                Label {
                    // The installed CLI's version beside the
                    // name, as probed once at launch.
                    Text("""
                    \(kind.displayName)\(Text(choices(kind).version.map { " " + $0 } ?? "")
                        .foregroundStyle(.secondary))
                    """)
                } icon: {
                    agentIcon(Image(kind.iconAssetName))
                }
                .tag(kind)
                .disabled(choices(kind).isAvailable == false)
            }
        }
        .hoverHelp("The agent CLI to run")
    }

    /// A model or effort picked for one agent may not exist on
    /// another, and neither does the empty string a form opens on the
    /// first time: either way the picker falls back to what this
    /// agent itself would run, so there is always something chosen to
    /// start with.
    private func resetUnavailableChoices() {
        if showsAgent, choices(agent).isAvailable == false,
           let available = AgentKind.allCases.first(where: { choices($0).isAvailable })
        {
            agent = available
        }
        let selected = choices(agent).selection(model: model, effort: effort)
        model = selected.model
        effort = selected.effort
    }
}
