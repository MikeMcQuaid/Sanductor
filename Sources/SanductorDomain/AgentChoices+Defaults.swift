public extension AgentChoices {
    /// The Mac publishes the same per-model choices for phone and SSH sessions.
    init(agent: AgentKind, defaults: [String: String]) {
        let prefix = agent.rawValue + "-"
        let models = (defaults[prefix + "models"] ?? "").split(separator: " ").map(String.init)
        self.init(
            models: models,
            efforts: [],
            defaultModel: defaults[prefix + "model"] ?? "",
            defaultEffort: defaults[prefix + "effort"] ?? "",
            modelEfforts: Dictionary(uniqueKeysWithValues: models.map { model in
                (model, (defaults[prefix + model + "-efforts"] ?? "").split(separator: " ").map(String.init))
            }),
            modelDefaultEfforts: Dictionary(uniqueKeysWithValues: models.map { model in
                (model, defaults[prefix + model + "-default-effort"] ?? "")
            }),
            names: Dictionary(uniqueKeysWithValues: models.map { model in
                (model, defaults[prefix + model + "-name"] ?? AgentOptionName.display(model))
            }),
            isAvailable: models.isEmpty == false,
        )
    }
}
