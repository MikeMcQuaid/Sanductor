import SanductorDomain
import Testing

struct AgentChoicesTests {
    @Test
    func `model changes reset efforts using that model alone`() {
        let choices = AgentChoices(
            models: ["gpt-6-sol", "gpt-6-luna", "legacy"],
            efforts: ["ultra", "max", "high"],
            defaultModel: "gpt-6-sol",
            defaultEffort: "ultra",
            modelEfforts: ["gpt-6-sol": ["ultra", "max"], "gpt-6-luna": ["max", "high"]],
            modelDefaultEfforts: ["gpt-6-luna": "high"],
        )
        #expect(choices.selection(model: "gpt-6-luna", effort: "ultra").effort == "high")
        #expect(choices.selection(model: "legacy", effort: "ultra").effort.isEmpty)
        #expect(choices.selection(model: "removed", effort: "high").model == "gpt-6-sol")
        for model in choices.models {
            let selection = choices.selection(model: model, effort: "ultra")
            #expect(choices.supports(model: selection.model, effort: selection.effort))
        }
        #expect(choices.supports(model: "gpt-6-luna", effort: "ultra") == false)
        #expect(choices.supports(model: "legacy", effort: "high") == false)
        #expect(choices.supports(model: "removed", effort: "") == false)
    }

    @Test
    func `agents without discovered models start on the CLI's own default`() {
        let choices = AgentChoices(models: [], efforts: ["high"], defaultModel: "", defaultEffort: "")
        #expect(choices.supports(model: "", effort: ""))
        #expect(choices.supports(model: "", effort: "high") == false)
    }

    @Test
    func `phone choices use the published per-model catalogue`() {
        let choices = AgentChoices(agent: .claudeCode, defaults: [
            "claude-models": "fable haiku", "claude-model": "fable", "claude-effort": "max",
            "claude-efforts": "ultra max high", "claude-fable-efforts": "max high",
            "claude-fable-name": "Fable 5.2", "claude-fable-default-effort": "high",
        ])
        #expect(choices.names["fable"] == "Fable 5.2")
        #expect(choices.supports(model: "fable", effort: "max"))
        #expect(choices.supports(model: "fable", effort: "ultra") == false)
        #expect(choices.selection(model: "haiku", effort: "max").effort.isEmpty)
        #expect(choices.selection(model: "fable", effort: "invalid").effort == "high")
    }

    @Test
    func `launch validation rejects unknown models and effort-only overrides`() {
        let catalogue = AgentModelCatalogue(models: ["fable", "haiku"], efforts: ["fable": ["max", "high"]])
        #expect(catalogue.supports(model: nil, effort: nil))
        #expect(catalogue.supports(model: "fable", effort: "max"))
        #expect(catalogue.supports(model: "haiku", effort: nil))
        #expect(catalogue.supports(model: "fable", effort: "ultra") == false)
        #expect(catalogue.supports(model: "haiku", effort: "high") == false)
        #expect(catalogue.supports(model: "removed", effort: nil) == false)
        #expect(catalogue.supports(model: nil, effort: "max") == false)
    }
}
