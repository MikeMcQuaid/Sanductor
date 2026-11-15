import SanductorDomain
import SwiftUI

/// The shared agent mark, monochrome unless its original colours are requested.
public struct AgentIcon: View {
    // MARK: Lifecycle

    public init(_ agent: AgentKind, size: CGFloat, coloured: Bool = false) {
        self.agent = agent
        self.size = size
        self.coloured = coloured
    }

    // MARK: Public

    public var body: some View {
        Image(coloured ? agent.connectedIconAssetName : agent.iconAssetName)
            .renderingMode(coloured ? .original : .template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(agent.displayName)
    }

    // MARK: Private

    private let agent: AgentKind
    private let size: CGFloat
    private let coloured: Bool
}
