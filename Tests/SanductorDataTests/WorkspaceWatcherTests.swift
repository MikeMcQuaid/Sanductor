import Foundation
@testable import SanductorData
import Synchronization
import Testing

struct WorkspaceWatcherTests {
    @Test
    func `repeated event batches do not grow the callback stack`() async {
        await #expect(processExitsWith: .success) {
            let calls = Mutex(0)
            let batches = 20_000
            await withCheckedContinuation { continuation in
                DispatchQueue(label: "watcher-regression").async {
                    let box = WorkspaceWatcher.ChangeBox(roots: ["/workspace"])
                    box.onChange.withLock { handler in
                        handler = WorkspaceWatcher.Handler { calls.withLock { $0 += 1 } }
                    }
                    for _ in 0 ..< batches {
                        box.record(["/workspace/repository/file"])
                    }
                    continuation.resume()
                }
            }
            #expect(calls.withLock { $0 } == batches)
        }
    }
}
