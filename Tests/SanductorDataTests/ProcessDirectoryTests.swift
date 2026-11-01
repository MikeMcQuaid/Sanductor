import Foundation
import SanductorData
import Testing

struct ProcessDirectoryTests {
    @Test(arguments: [false, true], [nil, 1_024] as [Int?])
    func `commands use an explicit directory or a neutral root`(explicit: Bool, limit: Int?) async throws {
        let root = try TestSupport.temporaryDirectory("process-directory")
        defer { try? FileManager.default.removeItem(atPath: root) }
        for command in [["/bin/pwd", "-P"], ["/usr/bin/printenv", "PWD"]] {
            let result = try await FoundationProcessRunner().run(
                command,
                workingDirectory: explicit ? root : nil,
                environment: ["PWD": root + "/Documents"],
                outputLimit: limit,
            )
            #expect(result.succeeded)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == (explicit ? root : "/"))
        }
    }
}
