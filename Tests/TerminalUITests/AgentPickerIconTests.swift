import AppKit
import SanductorDomain
@testable import SanductorInterface
import SwiftUI
import Testing

@MainActor
struct AgentPickerIconTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func `the Codex picker icon stays visible when its parent foreground matches the background`(
        scheme: ColorScheme,
    ) throws {
        let fixture = ImageRenderer(content: Rectangle().fill(Color.black).frame(width: 24, height: 24))
        let image = try NSImage(cgImage: #require(fixture.cgImage), size: NSSize(width: 24, height: 24))
        image.isTemplate = true
        let pickers = AgentOptionPickers(
            agent: .constant(.codexCLI), model: .constant(""), effort: .constant(""),
        ) { _ in
            AgentChoices(models: [], efforts: [], defaultModel: "", defaultEffort: "")
        }
        let renderer = ImageRenderer(content: pickers.agentIcon(Image(nsImage: image))
            .foregroundStyle(scheme == .light ? .white : .black)
            .padding(2)
            .background(scheme == .light ? Color.white : .black)
            .environment(\.colorScheme, scheme))
        let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        let colour = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.deviceRGB))
        #expect((colour.redComponent < 0.5) == (scheme == .light))
        #expect((colour.greenComponent < 0.5) == (scheme == .light))
        #expect((colour.blueComponent < 0.5) == (scheme == .light))
    }
}
