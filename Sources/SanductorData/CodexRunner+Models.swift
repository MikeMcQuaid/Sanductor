import Foundation
import SanductorDomain

public extension CodexRunner {
    /// Keeps stdin open until model/list answers; EOF would cancel the request.
    /// One line with braced variables: sudo's login shell turns each
    /// newline into a line continuation and expands a bare `$name`.
    var modelListingCommand: [String] {
        [
            "/bin/zsh -fc " + [
                "coproc codex app-server",
                "model_listing_pid=${!}",
                #"trap 'kill "${model_listing_pid}" &>/dev/null' EXIT"#,
                #"print -p -r -- '{"id":1,"method":"initialize","#
                    + #""params":{"clientInfo":{"name":"sanductor","version":"1"}}}'"#,
                #"while IFS= read -r -p -t 30 reply; do [[ "${reply}" == *'"id":1,'* ]] && break; done"#,
                #"print -p -r -- '{"method":"initialized"}'"#,
                #"print -p -r -- '{"id":2,"method":"model/list","params":{"includeHidden":false,"limit":100}}'"#,
                #"while IFS= read -r -p -t 30 reply; do"#
                    + #" if [[ "${reply}" == *'"id":2,'* ]]; then print -r -- "${reply}"; exit 0; fi; done"#,
                "exit 1",
            ]
            .joined(separator: "; ")
            .shellQuoted,
        ]
    }

    /// Reads the CLI's visible models and account-specific reasoning levels.
    func modelCatalogue(from output: String) -> AgentModelCatalogue? {
        guard let data = output.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = response["result"] as? [String: Any],
              let entries = result["data"] as? [[String: Any]]
        else {
            return nil
        }

        var models = [String]()
        var efforts = [String: [String]]()
        var defaults = [String: String]()
        for entry in entries {
            guard let slug = entry["model"] as? String,
                  entry["hidden"] as? Bool == false,
                  slug != "gpt-reserve", slug != "codex-auto-review"
            else {
                continue
            }

            models.append(slug)
            efforts[slug] = (entry["supportedReasoningEfforts"] as? [[String: Any]])?
                .compactMap { $0["reasoningEffort"] as? String } ?? []
            defaults[slug] = entry["defaultReasoningEffort"] as? String
        }
        return models.isEmpty ? nil : AgentModelCatalogue(models: models, efforts: efforts, defaultEfforts: defaults)
    }
}
