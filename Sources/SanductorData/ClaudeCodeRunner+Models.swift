import Foundation
import SanductorDomain

public extension ClaudeCodeRunner {
    /// Initialises the SDK without submitting a prompt or saving a session.
    var modelListingCommand: [String] {
        [
            "printf '%s\\n' "
                + #"'{"type":"control_request","request_id":"models","request":{"subtype":"initialize"}}'"#
                + " | " + executable
                + " --print --input-format stream-json --output-format stream-json"
                + " --verbose --no-session-persistence --safe-mode",
        ]
    }

    /// Reads the SDK response, ignoring unrelated events.
    func modelCatalogue(from output: String) -> AgentModelCatalogue? {
        for line in output.split(separator: "\n") {
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  envelope["type"] as? String == "control_response",
                  let response = envelope["response"] as? [String: Any],
                  response["subtype"] as? String == "success",
                  let payload = response["response"] as? [String: Any],
                  let models = payload["models"] as? [[String: Any]]
            else {
                continue
            }

            var names = [String: String]()
            var efforts = [String: [String]]()
            for model in models {
                guard let value = model["value"] as? String, value != "default",
                      let name = model["displayName"] as? String
                else {
                    continue
                }

                names[value] = name
                efforts[value] = model["supportedEffortLevels"] as? [String] ?? []
            }
            guard names.isEmpty == false else {
                return nil
            }

            return AgentModelCatalogue(models: Array(names.keys), names: names, efforts: efforts)
        }
        return nil
    }
}
