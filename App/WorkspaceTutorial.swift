import DashboardFeature
import Foundation
import SanductorInterface
import SwiftUI

/// Native popovers share one tour state and anchor to the actual pane bounds.
struct WorkspaceTutorial: ViewModifier {
    // MARK: Internal

    let model: SetupModel
    let step: SetupTourStep
    let sandboxUser: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Color.clear
                .frame(width: 1, height: 1)
                .padding(.top, Self.anchorInset)
                .popover(
                    isPresented: Binding(
                        get: { model.tutorialStep == step && model.isReady && model.isChecking == false },
                        set: { presented in
                            if presented == false, model.tutorialStep == step, model.isChecking == false {
                                model.finishTutorial()
                            }
                        },
                    ),
                    arrowEdge: .top,
                ) {
                    explanation
                }
        }
    }

    // MARK: Private

    private static let anchorInset: CGFloat = 80
    private static let spacing: CGFloat = 16
    private static let width: CGFloat = 360

    private var interfaceStyle: InterfaceStyle = .init()

    private var title: String {
        switch step {
        case .repositories:
            "Left: your repositories"

        case .agent:
            "Middle: your sandboxed agent"

        case .tools:
            "Right: your review and tools"
        }
    }

    private var message: Text {
        switch step {
        case .repositories:
            Text("""
            Add a repository here, then start an agent in a worktree: a separate checkout for its branch. \
            Repositories live under \(monospaced("/Users/Shared/sv-" + NSUserName())), \
            where \(monospaced(NSUserName())) and \(monospaced(sandboxUser)) can both write.
            """)

        case .agent:
            Text("""
            Agents run as \(monospaced(sandboxUser)), a separate non-admin user, \
            without access to your home or GitHub credentials, even in YOLO mode. \
            They can change shared files and send readable code over the network, \
            so treat their output as untrusted. Agents keep running when you quit Sanductor.
            """)

        case .tools:
            Text("""
            Review diffs, checks and files here before committing or running suggested commands. \
            Shell runs as \(monospaced(NSUserName())), with your normal permissions: use it in the main checkout \
            to bootstrap dependencies agents cannot install, such as Homebrew packages. \
            Shell tabs close when you quit the app.
            """)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(title)
                .interfaceFont(.headline)
            message
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(String(step.rawValue + 1)) of 3")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(step == .tools ? "Get started" : "Next", action: model.advanceTutorial)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: Self.width)
        .interfaceFont(.body)
        .onExitCommand(perform: model.finishTutorial)
    }

    private func monospaced(_ text: String) -> Text {
        Text(verbatim: text).font(interfaceStyle.font(.body, monospaced: true))
    }
}
