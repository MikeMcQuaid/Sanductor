import SanductorRemote

extension MobileModel {
    func requestRefresh(_ client: RemoteHerdr, includingPreferences: Bool = false) {
        refreshAgain = true
        refreshPreferences = refreshPreferences || includingPreferences
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            defer {
                if remote === client {
                    refreshTask = nil
                }
            }
            repeat {
                refreshAgain = false
                let withPreferences = refreshPreferences
                refreshPreferences = false
                do {
                    try await read(client, includingPreferences: withPreferences)
                } catch {
                    if Task.isCancelled == false, remote === client {
                        self.error = configuration.errorMessage(error)
                    }
                }
            } while refreshAgain && Task.isCancelled == false
        }
    }
}
