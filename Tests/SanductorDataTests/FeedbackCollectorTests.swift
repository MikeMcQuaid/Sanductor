import Foundation
@testable import SanductorData
import Synchronization
import Testing

struct FeedbackCollectorTests {
    @Test
    func `throttling restarts after a backwards clock correction`() async {
        let collector = FeedbackCollector()
        let calls = Mutex(0)
        for (time, expected) in [(1_000.0, 1), (1_059, 1), (999, 2), (1_058, 2), (1_059, 3)] {
            await collector.start("cleanup", minimumInterval: 60, now: Date(timeIntervalSince1970: time)) {
                calls.withLock { $0 += 1 }
            }
            await collector.wait("cleanup")
            #expect(calls.withLock { $0 } == expected)
        }
    }
}
