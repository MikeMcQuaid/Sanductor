#if os(iOS)
    import SanductorCloud
    import SanductorInterface
    import SanductorRemote
    import SwiftUI

    struct MobileSettings: View {
        // MARK: Lifecycle

        init(model: MobileModel) {
            self.model = model
            _configuration = State(initialValue: model.configuration)
        }

        // MARK: Internal

        var body: some View {
            NavigationStack {
                form
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            BusyButton(
                                "Connect",
                                busy: "Connecting",
                                prominent: true,
                                disabled: configuration.isValid == false,
                            ) {
                                model.configuration = configuration
                                model.selection = nil
                                model.reconnect()
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                    }
                    .onAppear { focus = "Home" }
            }
        }

        // MARK: Private

        private static let terminalSizeRange = 8.0 ... 30.0

        @Environment(\.dismiss)
        private var dismiss
        @State private var configuration: SSHConfiguration
        @FocusState private var focus: String?
        @AppStorage(CodeStyle.fontSizeKey)
        private var terminalSize: Double = CodeStyle.defaultPointSize
        @AppStorage(MobileModel.receiveKey(.done))
        private var receivesFinished = true
        @AppStorage(MobileModel.receiveKey(.blocked))
        private var receivesNeedsInput = true

        private let model: MobileModel
        private var nameStyle: NameStyle = .init()

        private var form: some View {
            Form {
                Section("Connection") {
                    Picker("Address", selection: $configuration.route) {
                        ForEach(SSHConfiguration.Route.allCases, id: \.self) { route in
                            Text(route.rawValue).tag(route)
                        }
                    }
                }
                endpoint("Home", host: $configuration.host, port: $configuration.port)
                endpoint("Away (optional)", host: $configuration.awayHost, port: $configuration.awayPort)
                connection
                terminalAndAlerts
                Section {
                    Picker("Herdr session", selection: $configuration.session) {
                        Text("sanductor").tag("sanductor")
                        Text("sanductor-dev").tag("sanductor-dev")
                    }
                    .pickerStyle(.menu)
                } footer: { Text("Use sanductor for the installed Mac app, or sanductor-dev for a development build.") }
                Section {
                    Text(model.publicKey).font(nameStyle.font).textSelection(.enabled)
                    ShareLink("Share public key", item: model.publicKey)
                } header: { Text("Phone's SSH key") } footer: {
                    Text("Add this public key to the sandbox user's authorised keys on your Mac. "
                        + "The private key stays in this phone's Keychain.")
                }
                Section {
                    Button("Forget saved host keys", role: .destructive) { model.forgetHost() }
                } footer: { Text("Use this only after verifying that your Mac's SSH host key has changed.") }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        @ViewBuilder private var terminalAndAlerts: some View {
            Section("Terminal") {
                Stepper("Font size: " + String(Int(terminalSize)), value: $terminalSize, in: Self.terminalSizeRange)
            }
            Section {
                Toggle("Agent finished", isOn: $receivesFinished)
                    .disabled(MobileModel.macWithholds(.done, in: model.defaults))
                Toggle("Agent needs input", isOn: $receivesNeedsInput)
                    .disabled(MobileModel.macWithholds(.blocked, in: model.defaults))
            } header: { Text("Mac alerts") } footer: {
                Text(model.notificationError
                    ?? "Your Mac sends these through iCloud while you're away from it, once Send to iPhone "
                    + "is on in its Settings → Notifications. Each applies to every iPhone on this iCloud account.")
            }
            .onChange(of: receivesFinished) { model.updateNotifications() }
            .onChange(of: receivesNeedsInput) { model.updateNotifications() }
        }

        private var connection: some View {
            Section {
                LabeledContent("Sandbox username") {
                    HStack(spacing: 0) {
                        Text(SSHConfiguration.usernamePrefix).foregroundStyle(.secondary)
                        TextField("Mac username", text: Binding(
                            get: { String(configuration.username.dropFirst(SSHConfiguration.usernamePrefix.count)) },
                            set: { configuration.username = SSHConfiguration.usernamePrefix + $0 },
                        ))
                    }
                }
            } header: { Text("SSH connection") } footer: {
                Text("Automatic tries Home, then Away when Home cannot be reached. "
                    + "Both addresses use the same sandbox username and herdr session.")
            }
        }

        private func endpoint(_ title: String, host: Binding<String>, port: Binding<Int>) -> some View {
            Section(title) {
                TextField("IP address or hostname", text: host)
                    .keyboardType(.URL)
                    .focused($focus, equals: title)
                LabeledContent("SSH port") {
                    TextField("22", value: port, format: .number.grouping(.never)).keyboardType(.numberPad)
                }
            }
        }
    }
#endif
