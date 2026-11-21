import SanductorDomain
import SwiftUI

/// Reader drafts belong only to the visible native text field.
public struct ReaderReplyField: View {
    // MARK: Lifecycle

    public init(send: @escaping (ReaderReply) async throws -> Void) {
        self.send = send
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Reply to agent", text: Binding(get: { draft }, set: { value in
                    if ReaderReply.accepts(value) {
                        draft = value
                        error = nil
                    } else {
                        error = "Enter a single line of up to 1,000 bytes."
                    }
                }))
                .focused($focused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { Task {
                    await submit()
                }
                }
                BusyButton("Send", busy: "Sending", prominent: true, disabled: ReaderReply(draft) == nil) {
                    await submit()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            if let error {
                Text(error).interfaceFont(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Self.fieldInset)
        .disabled(sending)
        .onAppear { focused = true }
    }

    // MARK: Private

    private static let fieldInset: CGFloat = 8

    @State private var draft = ""
    @State private var error: String?
    @State private var sending = false
    @FocusState private var focused: Bool

    private let send: (ReaderReply) async throws -> Void

    private func submit() async {
        guard sending == false, let reply = ReaderReply(draft) else {
            return
        }

        sending = true
        defer { sending = false; focused = true }
        do {
            try await send(reply)
            draft = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
