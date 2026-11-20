import SanductorData
import SanductorInterface
import SwiftUI

/// A write-only field, including when rotating an existing key.
struct SecretEditorSheet: View {
    // MARK: Internal

    let existing: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(existing.map { "Replace secret “" + $0 + "”" } ?? "Add secret")
                .interfaceFont(.headline)
            Form {
                if existing == nil {
                    TextField("Name", text: $name, prompt: Text("SENTRY_TOKEN"))
                        .focused($focus, equals: .name)
                }
                SecureField("Secret value", text: $value)
                    .privacySensitive()
                    .focused($focus, equals: .value)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                BusyButton("Save", busy: "Saving", prominent: true, disabled: cannotSave, action: save)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .frame(width: Self.width)
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onAppear { focus = existing == nil ? .name : .value }
        .onDisappear { value = "" }
    }

    // MARK: Private

    private enum Field { case name, value }

    private static let width: CGFloat = 440

    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var focus: Field?
    @State private var name = ""
    @State private var value = ""
    @State private var error: String?
    @State private var saving = false

    private var cannotSave: Bool {
        value.isEmpty || (existing ?? name).isEmpty
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await PromptSecrets.save(name: existing ?? name, value: value, replacing: existing != nil)
            value = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
