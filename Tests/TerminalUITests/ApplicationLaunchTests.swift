@testable import SanductorInterface
import Testing

struct ApplicationLaunchTests {
    @Test(arguments: [false, true])
    func `launch runs once regardless of callback registration order`(applicationFirst: Bool) {
        let launch = ApplicationLaunch()
        var starts = 0
        if applicationFirst {
            launch.didFinishLaunching()
        }
        launch.whenReady { starts += 1 }
        #expect(starts == (applicationFirst ? 1 : 0))
        launch.didFinishLaunching()
        #expect(starts == 1)
        launch.whenReady { starts += 1 }
        launch.didFinishLaunching()
        #expect(starts == 1)
    }
}
