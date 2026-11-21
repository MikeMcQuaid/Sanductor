import SanductorDomain
import SanductorInterface
import SwiftUI

struct SavedPromptLabel: View {
    // MARK: Internal

    let prompt: SavedPrompt
    let owner: String?

    var body: some View {
        Label {
            Text(prompt.name)
        } icon: {
            OwnerAvatar(owner: owner, size: Self.iconSize).menuImage
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: Private

    private static let iconSize: CGFloat = 14
}
