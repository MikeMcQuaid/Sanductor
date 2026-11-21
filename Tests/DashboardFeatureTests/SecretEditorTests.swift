import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

@MainActor
struct SecretEditorTests {
    // MARK: Internal

    @Test(arguments: [nil, "Existing service"])
    func `adding and rotating use an empty native password field`(existing: String?) async throws {
        let host = NSHostingView(rootView: SecretEditorSheet(existing: existing))
        let window = SessionNavigationTests.Fixture.window(hosting: host)
        defer { window.close() }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let field = try #require(passwordField(in: host))
        #expect(field.stringValue.isEmpty)
    }

    // MARK: Private

    private func passwordField(in view: NSView) -> NSSecureTextField? {
        if let field = view as? NSSecureTextField {
            return field
        }
        return view.subviews.lazy.compactMap { passwordField(in: $0) }.first
    }
}
