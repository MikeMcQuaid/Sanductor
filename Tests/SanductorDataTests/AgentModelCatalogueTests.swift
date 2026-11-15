import Foundation
@testable import SanductorData
import Testing

struct AgentModelCatalogueTests {
    @Test
    func `the Claude SDK names unused aliases and orders families before versions`() throws {
        let output = """
        {
          "type": "control_response",
          "response": {
            "subtype": "success",
            "response": {
              "models": [
                {
                  "value": "sonnet",
                  "displayName": "Sonnet 5.5"
                },
                {
                  "value": "opus",
                  "displayName": "Opus 5.5"
                },
                {
                  "value": "claude-fable-5-1",
                  "displayName": "Fable 5.1"
                },
                {
                  "value": "fable",
                  "displayName": "Fable 5.2",
                  "supportedEffortLevels": [
                    "low",
                    "high",
                    "max"
                  ]
                }
              ]
            }
          }
        }
        """.replacing("\n", with: "")
        let catalogue = try #require(ClaudeCodeRunner().modelCatalogue(from: output))
        #expect(catalogue.models == ["fable", "claude-fable-5-1", "opus", "sonnet"])
        #expect(catalogue.names["fable"] == "Fable 5.2")
        #expect(catalogue.names["sonnet"] == "Sonnet 5.5")
        #expect(catalogue.efforts["sonnet"]?.isEmpty == true)
        #expect(catalogue.efforts["fable"] == ["max", "high", "low"])
    }

    @Test
    func `the Codex families precede numeric versions and hidden models stay hidden`() throws {
        let output = """
        {
          "result": { "data": [
            {
              "model": "gpt-6-sol",
              "hidden": false,
              "supportedReasoningEfforts": [
                {
                  "reasoningEffort": "ultra"
                },
                {
                  "reasoningEffort": "max"
                },
                {
                  "reasoningEffort": "xhigh"
                }
              ]
            },
            {
              "model": "gpt-6.1-sol",
              "hidden": false
            },
            {
              "model": "gpt-6-astra",
              "hidden": false
            },
            {
              "model": "gpt-6.10-sol",
              "hidden": false
            },
            {
              "model": "gpt-reserve",
              "hidden": true
            }
          ] }
        }
        """.replacing("\n", with: "")
        let catalogue = try #require(CodexRunner().modelCatalogue(from: output))
        #expect(catalogue.models == ["gpt-6-astra", "gpt-6.10-sol", "gpt-6.1-sol", "gpt-6-sol"])
        #expect(catalogue.efforts["gpt-6-sol"] == ["ultra", "max", "xhigh"])
    }
}
