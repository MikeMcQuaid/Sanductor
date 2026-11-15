import Foundation
@testable import MobileFeature
import NIOCore
import SanductorRemote
import Testing

extension MobileConnectionTests {
    @Test
    func `automatic connection tries away after a home transport failure`() async throws {
        var configuration = SSHConfiguration()
        configuration.host = "192.168.1.2"
        configuration.awayHost = "mac.example.com"
        configuration.awayPort = 2_222
        configuration.username = "sandvault-test"
        let model = MobileModel(configuration: configuration)
        var destinations = [String]()
        model.connectRemote = { _, timeout in
            destinations.append(model.activeConfiguration?.hostIdentity ?? "")
            if destinations.count == 1 {
                #expect(timeout == 1)
                throw ChannelError.connectTimeout(.seconds(1))
            }
            #expect(timeout == nil)
        }
        _ = try await model.connectEndpoint()
        #expect(destinations == ["192.168.1.2:22", "mac.example.com:2222"])
        #expect(model.configuration == configuration)
        #expect(model.activeConfiguration?.hostIdentity == "mac.example.com:2222")
    }

    @Test(arguments: [SSHHostKeyError.unknown("key"), .changed])
    func `host verification never falls through to another endpoint`(failure: SSHHostKeyError) async {
        var configuration = SSHConfiguration()
        configuration.host = "home"
        configuration.awayHost = "away"
        configuration.username = "sandvault-test"
        let model = MobileModel(configuration: configuration)
        var attempts = 0
        model.connectRemote = { _, _ in attempts += 1; throw failure }
        await #expect(throws: SSHHostKeyError.self) { try await model.connectEndpoint() }
        #expect(attempts == 1)
        #expect(model.activeConfiguration?.hostIdentity == "home:22")
    }

    @Test
    func `an explicit away selection never tries the home address`() async throws {
        var configuration = SSHConfiguration()
        configuration.host = "home"
        configuration.awayHost = "away"
        configuration.username = "sandvault-test"
        configuration.route = .away
        let model = MobileModel(configuration: configuration)
        model.connectRemote = { _, timeout in
            #expect(model.activeConfiguration?.hostIdentity == "away:22")
            #expect(timeout == nil)
        }
        _ = try await model.connectEndpoint()
    }
}
