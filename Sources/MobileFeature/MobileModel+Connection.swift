import SanductorRemote

extension MobileModel {
    /// Reevaluate both endpoints on reconnect; an established connection is kept across app switches.
    func connectEndpoint() async throws -> RemoteHerdr {
        let candidates = configuration.connectionCandidates
        for (index, endpoint) in candidates.enumerated() {
            try Task.checkCancellation()
            activeConfiguration = endpoint
            let client = RemoteHerdr(configuration: endpoint)
            remote = client
            progress.report("Connecting to " + endpoint.hostIdentity)
            do {
                try await connectRemote(client, index < candidates.count - 1 ? Self.homeTimeout : nil)
                try Task.checkCancellation()
                return client
            } catch {
                await client.disconnect()
                try Task.checkCancellation()
                guard index < candidates.count - 1, SSHConfiguration.canTryAnotherEndpoint(after: error) else {
                    throw error
                }
            }
        }
        throw RemoteError("Enter a home or away address.")
    }

    private static let homeTimeout: Int64 = 1
}
