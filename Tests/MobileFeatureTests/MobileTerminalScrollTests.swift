@testable import MobileFeature
import Testing

struct MobileTerminalScrollTests {
    @Test
    func `dragging preserves fractional lines in both directions`() {
        var scroll = MobileTerminalScroll()
        #expect(scroll.move(lines: 1.75) == 1)
        #expect(scroll.move(lines: 0.25) == 1)
        #expect(scroll.move(lines: -0.75) == 0)
        #expect(scroll.move(lines: -0.25) == -1)
    }

    @Test(arguments: [60, 120], [-100.0, 100.0])
    func `flicks coast beyond the drag and settle at either refresh rate`(frames: Int, velocity: Double) {
        var scroll = MobileTerminalScroll()
        scroll.velocity = velocity
        var lines = 0
        for _ in 0 ..< frames * 5 {
            lines += scroll.advance(seconds: 1 / Double(frames), decelerationRate: 0.998)
        }
        #expect(lines == (velocity > 0 ? 49 : -49))
        #expect(scroll.velocity == 0)
        #expect(scroll.advance(seconds: 1, decelerationRate: 0.998) == 0)
    }

    @Test
    func `resetting cancels momentum and fractional movement`() {
        var scroll = MobileTerminalScroll()
        #expect(scroll.move(lines: 0.75) == 0)
        scroll.velocity = 100
        scroll = MobileTerminalScroll()
        #expect(scroll.advance(seconds: 1, decelerationRate: 0.998) == 0)
        #expect(scroll.move(lines: 0.25) == 0)
    }
}
