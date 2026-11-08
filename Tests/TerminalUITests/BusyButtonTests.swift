import AppKit
@testable import SanductorInterface
import SwiftUI
import Synchronization
import Testing

@MainActor
struct BusyButtonTests {
    @Test(arguments: [false, true])
    func `busy buttons retain click modifiers after they are released`(richLabel: Bool) async throws {
        let held = Mutex<EventModifiers>([.option, .command])
        var received: EventModifiers?
        var button = richLabel
            ? BusyButton(label: Text("Copy"), accessibilityLabel: "Copy", busy: "Copying") { received = $0 }
            : BusyButton("Copy", busy: "Copying") { received = $0 }
        button.modifiers = { held.withLock { $0 } }
        let host = NSHostingView(rootView: button.frame(width: 160, height: 80))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0 ..< 10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: 80, y: 40),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1,
            ))
            window.sendEvent(event)
        }
        held.withLock { $0 = [] }
        for _ in 0 ..< 100 where received == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(received == [.option, .command])
    }
}
