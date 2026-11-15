import SwiftUI

// MARK: - HoverHelp

public extension View {
    /// An explanatory tooltip on hover. SwiftUI's `.help` is applied
    /// too, but the AppKit tooltip is the one that reliably shows on
    /// the current macOS beta.
    func hoverHelp(_ text: String) -> some View {
        #if os(macOS)
            help(text).overlay(TooltipSurface(text: text))
        #else
            help(text)
        #endif
    }

    /// The same, closing with the control's keyboard shortcut in
    /// one shared style, so every tooltip teaches the key that
    /// presses its control.
    func hoverHelp(_ text: String, shortcut: String) -> some View {
        hoverHelp(text + " (" + shortcut + ")")
    }
}
