import SanductorData
import SanductorInterface
import SwiftUI

/// Named Keychain values the user can reference in prompts.
public struct SecretsSettingsPane: View {
    // MARK: Lifecycle

    public init() {
        // The pane reads names when opened.
    }

    // MARK: Public

    public var body: some View {
        Form {
            Section {
                if loaded == false {
                    ProgressView("Reading secret names…")
                }
                ForEach(names, id: \.self) { name in
                    secretRow(name)
                }
                Button("Add secret", systemImage: "plus") {
                    existing = nil
                    editing = true
                }
                .buttonStyle(.glass)
            } footer: {
                Text("Use $NAME in a prompt. The agent receives the value and its transcript may keep it.")
            }
            if let error {
                Text(error).foregroundStyle(.red)
                BusyButton("Retry", busy: "Reading") { await reload() }
            }
        }
        .formStyle(.grouped)
        .disabled(removing)
        .task { await reload() }
        .sheet(isPresented: $editing, onDismiss: refresh) { SecretEditorSheet(existing: existing) }
        .confirmationDialog(
            "Delete " + (existing ?? "") + "?", isPresented: $confirming, presenting: existing,
        ) { name in
            Button("Delete", role: .destructive) {
                Task {
                    removing = true
                    defer { removing = false }
                    do {
                        try await PromptSecrets.remove(name: name)
                        await reload()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var names: [String] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var existing: String?
    @State private var editing = false
    @State private var confirming = false
    @State private var removing = false

    private func secretRow(_ name: String) -> some View {
        HStack {
            Text(PromptSecrets.reference(name)).textSelection(.enabled)
            Spacer()
            Button("Replace") {
                existing = name
                editing = true
            }
            .buttonStyle(.glass)
            Button("Delete " + name, systemImage: "trash", role: .destructive) {
                existing = name
                confirming = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .hoverHelp("Delete " + name)
        }
    }

    private func refresh() {
        Task {
            await reload()
        }
    }

    private func reload() async {
        do {
            names = try await PromptSecrets.names()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}
