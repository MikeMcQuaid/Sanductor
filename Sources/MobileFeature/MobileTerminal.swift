#if os(iOS)
    import SanductorDomain
    import SanductorInterface
    import SanductorRemote
    import SwiftTerm
    import SwiftUI
    import UIKit

    struct MobileTerminal: UIViewRepresentable {
        // MARK: Internal

        final class Coordinator: NSObject, TerminalViewDelegate {
            // MARK: Lifecycle

            init(model: MobileModel, onReady: @escaping () -> Void, onHandoff: @escaping () -> Void) {
                self.model = model
                self.onReady = onReady
                self.onHandoff = onHandoff
                super.init()
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(stopScrolling),
                    name: UIApplication.willResignActiveNotification,
                    object: nil,
                )
            }

            deinit { /* The representable stops the stream. */ }

            // MARK: Internal

            weak var view: PhoneTerminalView?
            var scrolling: MobileTerminalScroll = .init()
            var scrollDisplayLink: CADisplayLink?
            var scrollTimestamp: CFTimeInterval?
            var scrollPoint: CGPoint = .zero

            var stream: SSHCommand?

            func start(session: MobileSession, view: PhoneTerminalView) {
                guard task == nil, view.bounds.width > 1, view.bounds.height > 1 else {
                    return
                }

                task = Task { [weak self] in
                    await self?.attach(session: session, view: view)
                }
            }

            func stop() {
                stopScrolling()
                task?.cancel()
                task = nil
                stream?.close()
                stream = nil
            }

            func sendBytes(_ bytes: [UInt8]) {
                stopScrolling()
                stream?.send(Data((HerdrTerminal.inputCommand(bytes: bytes) + "\n").utf8))
            }

            func send(source _: TerminalView, data: ArraySlice<UInt8>) {
                sendBytes(Array(data))
            }

            func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
                guard newCols > 0, newRows > 0, stream != nil,
                      sentSize?.0 != newCols || sentSize?.1 != newRows
                else {
                    return
                }

                sentSize = (newCols, newRows)
                stream?.send(Data((HerdrTerminal.resizeCommand(columns: newCols, rows: newRows) + "\n").utf8))
            }

            func setTerminalTitle(source _: TerminalView, title _: String) {
                // Navigation owns the title.
            }

            func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
                // Directories come from herdr.
            }

            func scrolled(source _: TerminalView, position _: Double) {
                // Herdr owns scrollback.
            }

            func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {
                // SwiftTerm owns rendering.
            }

            func requestOpenLink(source _: TerminalView, link: String, params _: [String: String]) {
                guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil
                else {
                    return
                }

                UIApplication.shared.open(url)
            }

            // MARK: Private

            private static let frameTimeout = 15

            private let model: MobileModel
            private let onReady: () -> Void
            private let onHandoff: () -> Void
            private var task: Task<Void, Never>?
            private var hasFrame = false
            private var handedOff = false
            private var sentSize: (Int, Int)?

            private func attach(session: MobileSession, view: PhoneTerminalView) async {
                do {
                    let attached = try await model.terminal(paneID: session.id)
                    guard Task.isCancelled == false else {
                        attached.close()
                        return
                    }

                    stream = attached
                    let deadline = Task {
                        try? await Task.sleep(for: .seconds(Self.frameTimeout))
                        if Task.isCancelled == false {
                            attached.close()
                        }
                    }
                    defer { deadline.cancel(); stopScrolling(); attached.close(); stream = nil }
                    let dimensions = view.terminalDimensions
                    sizeChanged(source: view, newCols: dimensions.cols, newRows: dimensions.rows)
                    var lines = RemoteLines()
                    for try await data in attached.output {
                        try Task.checkCancellation()
                        for line in try lines.append(data) {
                            handle(line, deadline: deadline)
                        }
                    }
                } catch {
                    // Recovery below retries once, without replaying any input.
                }
                if handedOff == false, Task.isCancelled == false {
                    model.terminalDisconnected()
                }
            }

            private func handle(_ line: String, deadline: Task<Void, Never>) {
                switch HerdrTerminal.parse(line: line) {
                case let .frame(bytes):
                    view?.feed(byteArray: bytes[...])
                    deadline.cancel()
                    if hasFrame == false {
                        hasFrame = true
                        model.terminalReady()
                        onReady()
                    }

                case let .closed(reason):
                    if reason == HerdrTerminal.takeoverReason {
                        handedOff = true
                        stopScrolling()
                        stream?.close()
                        stream = nil
                        _ = view?.resignFirstResponder()
                        onHandoff()
                    }

                case nil:
                    break
                }
            }
        }

        let model: MobileModel
        let session: MobileSession
        let onReady: () -> Void
        let onHandoff: () -> Void
        let dark: Bool

        static func dismantleUIView(_ view: PhoneTerminalView, coordinator: Coordinator) {
            _ = view.resignFirstResponder()
            coordinator.stop()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(model: model, onReady: onReady, onHandoff: onHandoff)
        }

        func makeUIView(context: Context) -> PhoneTerminalView {
            let view = PhoneTerminalView(frame: .zero, font: style.uiKitFont)
            applyAppearance(to: view)
            view.changeScrollback(nil)
            view.agent = session.agent
            view.inputAccessoryView = PhoneKeyboard(terminal: view)
            view.terminalDelegate = context.coordinator
            view.onScrollStop = { [weak coordinator = context.coordinator] in
                coordinator?.stopScrolling()
            }
            view.onPaste = { [weak coordinator = context.coordinator] text in
                coordinator?.sendBytes(HerdrTerminal.pasteBytes(text))
            }
            view.onSize = { [weak coordinator = context.coordinator, weak view] in
                guard let view else {
                    return
                }

                coordinator?.start(session: session, view: view)
            }
            context.coordinator.view = view
            view.panGestureRecognizer.isEnabled = false
            view.addGestureRecognizer(UIPanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.scroll(_:)),
            ))
            return view
        }

        func updateUIView(_ view: PhoneTerminalView, context _: Context) {
            applyAppearance(to: view)
            view.agent = session.agent
            if view.font != style.uiKitFont {
                view.font = style.uiKitFont
            }
        }

        // MARK: Private

        private var style: CodeStyle = .init()

        private func applyAppearance(to view: PhoneTerminalView) {
            view.overrideUserInterfaceStyle = dark ? .dark : .light
            let background: UIColor = dark ? .black : .white
            guard view.nativeBackgroundColor != background else {
                return
            }

            view.nativeBackgroundColor = background
            view.nativeForegroundColor = dark ? .white : .black
        }
    }

    final class PhoneTerminalView: TerminalView {
        // MARK: Lifecycle

        deinit { /* The coordinator owns the connection. */ }

        // MARK: Internal

        var onPaste: ((String) -> Void)?
        var onSize: (() -> Void)?
        var onScrollStop: (() -> Void)?
        var shiftModifier = false

        var agent: AgentKind? {
            didSet {
                guard oldValue != agent, inputView != nil else {
                    return
                }

                inputView = PhoneKeyboard(terminal: self, expanded: true)
                reloadInputViews()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                // SwiftTerm retains Core Graphics if Metal cannot start.
                try? setUseMetal(true)
            } else {
                onScrollStop?()
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onScrollStop?()
            super.touchesBegan(touches, with: event)
        }

        override func insertText(_ text: String) {
            super.insertText(shiftModifier ? text.uppercased() : text)
            resetModifiers()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onSize?()
        }

        override func paste(_: Any?) {
            if let text = UIPasteboard.general.string {
                onPaste?(text)
            }
        }

        func resetModifiers() {
            controlModifier = false
            shiftModifier = false
            (inputAccessoryView as? PhoneKeyboard)?.updateModifiers()
            (inputView as? PhoneKeyboard)?.updateModifiers()
        }
    }
#endif
