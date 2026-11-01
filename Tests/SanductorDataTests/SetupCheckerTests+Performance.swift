@testable import SanductorData
import Testing

extension SetupCheckerTests {
    @Test
    func `completed setup does not probe unused signing availability`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = await fixture.checker.check(verifyOnline: false)
        #expect(fixture.runner.commands.withLock { commands in
            commands.contains { $0.contains("--list-secret-keys") || $0.contains("ssh-add") } == false
        })
    }

    @Test
    func `first setup verifies GitHub with one authenticated request`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let result = await fixture.checker.check(verifyOnline: true)
        #expect(result.issues.isEmpty)
        let commands = fixture.runner.commands.withLock { $0 }
        let requests = commands.count { $0.first == "gh" }
        #expect(requests == 1)
        #expect(commands.contains { $0.last?.contains("gh auth token") == true } == false)
    }
}
