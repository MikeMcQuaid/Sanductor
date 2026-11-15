import SanductorDomain
import SanductorInterface
import SwiftUI
import TerminalUI

struct SavedPromptMenu: View {
    let model: DashboardModel
    let repositoryPath: String?
    let insert: (String) -> Void

    var body: some View {
        let prompts = model.prompts.availablePrompts(repositoryPath: repositoryPath)
        return Menu("Saved prompts") {
            ForEach(prompts) { prompt in
                Button { insert(prompt.prompt) } label: {
                    SavedPromptLabel(
                        prompt: prompt,
                        owner: model.groups.first { $0.repository.path == prompt.repositoryPath }?.repository.owner,
                    )
                }
            }
            if prompts.isEmpty {
                Text("No saved prompts").disabled(true)
            }
            Divider()
            SettingsPaneLink("Manage saved prompts…", pane: "prompts")
        }
        .task(id: model.groups.compactMap(\.repository.owner)) {
            OwnerAvatar.preload(model.groups.compactMap(\.repository.owner))
        }
        .fixedSize()
        .hoverHelp("Insert saved text before the current draft, including this repository's scheduled prompts")
    }
}
