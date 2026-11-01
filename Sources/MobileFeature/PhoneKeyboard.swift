#if os(iOS)
    import SwiftTerm
    import UIKit

    final class PhoneKeyboard: UIInputView {
        // MARK: Lifecycle

        init(terminal: PhoneTerminalView, expanded: Bool = false) {
            self.terminal = terminal
            self.expanded = expanded
            super.init(frame: .zero, inputViewStyle: .keyboard)
            frame.size.height = intrinsicContentSize.height
            allowsSelfSizing = true
            let rows = UIStackView(arrangedSubviews: expanded ? extraRows() : [accessoryRow()])
            rows.axis = .vertical
            rows.spacing = Self.spacing
            rows.distribution = .fillEqually
            rows.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rows)
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
                rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
                rows.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
                rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
                heightAnchor.constraint(equalToConstant: intrinsicContentSize.height),
            ])
            updateModifiers()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateModifiers),
                name: .terminalViewControlModifierReset,
                object: terminal,
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Use init(terminal:expanded:)")
        }

        deinit { repeatTask?.cancel() }

        // MARK: Internal

        override var intrinsicContentSize: CGSize {
            let count: CGFloat = expanded ? Self.extraRowCount : 1
            return CGSize(
                width: UIView.noIntrinsicMetric,
                height: count * Self.keyHeight + (count - 1) * Self.spacing + Self.padding + Self.padding,
            )
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                repeatTask?.cancel()
            }
        }

        @objc
        func updateModifiers() {
            controlButton?.isSelected = terminal?.controlModifier ?? false
            shiftButton?.isSelected = terminal?.shiftModifier ?? false
        }

        // MARK: Private

        private static let keyHeight: CGFloat = 44
        private static let padding: CGFloat = 8
        private static let spacing: CGFloat = 4
        private static let extraRowCount: CGFloat = 4
        private static let repeatDelayMilliseconds = 600
        private static let repeatInterval: Duration = .milliseconds(100)

        private weak var terminal: PhoneTerminalView?
        private let expanded: Bool
        private var controlButton: UIButton?
        private var shiftButton: UIButton?
        private var repeatTask: Task<Void, Never>?

        private func accessoryRow() -> UIStackView {
            row([
                key("Esc", bytes: EscapeSequences.cmdEsc),
                key("Tab", bytes: EscapeSequences.cmdTab, image: "arrow.right.to.line.compact"),
                key("Up", bytes: EscapeSequences.moveUpNormal, image: "arrow.up", repeats: true),
                key("Down", bytes: EscapeSequences.moveDownNormal, image: "arrow.down", repeats: true),
                key("Return", bytes: Array("\r".utf8), image: "return"),
                button("Agent keys", image: "ellipsis") { [weak self] _ in
                    guard let target = self?.terminal else {
                        return
                    }

                    target.inputView = target.inputView == nil ? PhoneKeyboard(terminal: target, expanded: true) : nil
                    target.reloadInputViews()
                },
                button("Hide keyboard", image: "keyboard.chevron.compact.down") { [weak self] _ in
                    self?.repeatTask?.cancel()
                    self?.terminal?.resetModifiers()
                    _ = self?.terminal?.resignFirstResponder()
                },
            ])
        }

        private func extraRows() -> [UIStackView] {
            let control = button("Ctrl", image: "control") { [weak self] _ in
                self?.terminal?.controlModifier.toggle()
                self?.updateModifiers()
            }
            controlButton = control
            let shift = button("Shift", image: "shift") { [weak self] _ in
                self?.terminal?.shiftModifier.toggle()
                self?.updateModifiers()
            }
            shiftButton = shift
            var actions = [UIButton]()
            if let agent = terminal?.agent {
                actions = [
                    key("Queue", bytes: agent.queueInput, modifiers: false),
                    key("Send now", bytes: agent.sendInputNow, modifiers: false),
                ]
            }
            return [
                row([
                    key("Line start", bytes: Array("\u{01}".utf8), image: "arrow.left.to.line"),
                    key("Left", bytes: EscapeSequences.moveLeftNormal, image: "arrow.left", repeats: true),
                    key("Right", bytes: EscapeSequences.moveRightNormal, image: "arrow.right", repeats: true),
                    key("Line end", bytes: Array("\u{05}".utf8), image: "arrow.right.to.line"),
                ]),
                row([
                    key("Clear line", bytes: Array("\u{01}\u{0B}".utf8)),
                    key("Cut ←", bytes: Array("\u{15}".utf8)),
                    key("Word ⌫", bytes: Array("\u{17}".utf8)),
                    key("Paste cut", bytes: Array("\u{19}".utf8)),
                ]),
                row(actions + [key("New line", bytes: Array("\n".utf8))]),
                row([
                    control, shift, key("Space", bytes: Array(" ".utf8)),
                    key("History", bytes: Array("\u{12}".utf8)),
                ]),
            ]
        }

        private func row(_ buttons: [UIButton]) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: buttons)
            stack.spacing = Self.spacing
            stack.distribution = .fillEqually
            return stack
        }

        private func button(_ title: String, image: String? = nil, action: @escaping (Bool) -> Void) -> UIButton {
            let button = UIButton(type: .system)
            button.configuration = .glass()
            button.configurationUpdateHandler = { button in
                var config = button.isSelected ? UIButton.Configuration.prominentGlass() : .glass()
                config.title = image == nil ? title : nil
                config.image = image.flatMap { UIImage(systemName: $0) }
                config.contentInsets = NSDirectionalEdgeInsets(
                    top: Self.spacing, leading: Self.spacing, bottom: Self.spacing, trailing: Self.spacing,
                )
                config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var result = attributes
                    result.font = .preferredFont(forTextStyle: .caption1)
                    return result
                }
                button.configuration = config
            }
            button.accessibilityLabel = title
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            let activation = MobileKeyActivation { held in
                UIDevice.current.playInputClick()
                action(held)
            }
            button.addAction(UIAction { _ in activation.touchDown() }, for: .touchDown)
            button.addAction(UIAction { _ in activation.activate() }, for: .primaryActionTriggered)
            button.addAction(UIAction { _ in activation.cancelTouch() }, for: [.touchUpOutside, .touchCancel])
            return button
        }

        private func key(
            _ title: String, bytes: [UInt8], image: String? = nil, repeats: Bool = false, modifiers: Bool = true,
        ) -> UIButton {
            let button = button(title, image: image) { [weak self] held in
                guard let self, let terminal else {
                    return
                }

                repeatTask?.cancel()
                let modified = modifiers ? MobileTerminalKeys.modified(
                    bytes, shift: terminal.shiftModifier, control: terminal.controlModifier,
                ) : bytes
                terminal.send(modified)
                terminal.resetModifiers()
                if repeats, held {
                    repeatTask = Task { [weak terminal] in
                        do {
                            try await Task.sleep(for: .milliseconds(Self.repeatDelayMilliseconds))
                            while Task.isCancelled == false {
                                terminal?.send(modified)
                                try await Task.sleep(for: Self.repeatInterval)
                            }
                        } catch { /* Releasing the key stops its repeats. */ }
                    }
                }
            }
            button.addAction(UIAction { [weak self] _ in self?.repeatTask?.cancel() }, for: [
                .touchUpInside, .touchUpOutside, .touchCancel,
            ])
            return button
        }
    }
#endif
