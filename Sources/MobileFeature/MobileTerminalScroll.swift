import Darwin

/// Fractional lines and flick momentum for the phone's remote scrollback.
struct MobileTerminalScroll {
    // MARK: Internal

    var velocity = 0.0

    mutating func move(lines: Double) -> Int {
        remainder += lines
        let whole = Int(remainder)
        remainder -= Double(whole)
        return whole
    }

    mutating func advance(seconds: Double, decelerationRate: Double) -> Int {
        guard velocity != 0, seconds > 0 else {
            return 0
        }

        // UIKit's rate is per millisecond; integrate it across this frame.
        let friction = Darwin.log(decelerationRate) * Self.millisecondsPerSecond
        let decay = Darwin.exp(friction * seconds)
        let distance = velocity * (decay - 1) / friction
        velocity *= decay
        if abs(velocity) < Self.minimumVelocity {
            velocity = 0
        }
        return move(lines: distance)
    }

    // MARK: Private

    private static let minimumVelocity = 0.5
    private static let millisecondsPerSecond = 1_000.0

    private var remainder = 0.0
}
