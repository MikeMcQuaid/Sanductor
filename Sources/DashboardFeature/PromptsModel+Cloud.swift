import Foundation
import SanductorCloud
import SanductorData
import SanductorDomain
import TerminalUI

public extension PromptsModel {
    /// Coalesce activation, network recovery and edits made during an upload.
    func syncPrivateSettings() {
        guard let cloud, let portableSettings else {
            return
        }
        guard NetworkMonitor.shared.isOnline else {
            cloudStatus = "Private settings will back up when this Mac is online."
            return
        }

        cloudSyncRequested = true
        guard cloudTask == nil else {
            return
        }

        cloudTask = Task {
            defer { cloudTask = nil }
            repeat {
                cloudSyncRequested = false
                cloudStatus = "Checking the iCloud backup…"
                var retry = true
                while true {
                    do {
                        let available = try await cloud.synchronise { remote, account in
                            let data = try portableSettings.mergeCloudArchive(remote, account: account, store: store)
                            reloadPrompts()
                            return data
                        } saved: { data, account in
                            portableSettings.cloudArchiveSaved(data, account: account)
                        }
                        cloudStatus = available ? "Private settings are backed up to iCloud."
                            : "iCloud is unavailable. Private settings are saved on this Mac."
                        break
                    } catch {
                        guard retry else {
                            cloudStatus = "iCloud backup failed: " + error.localizedDescription
                            ErrorLog.shared.report(cloudStatus)
                            break
                        }

                        retry = false
                        PerformanceLog.recordMessage(
                            "Retrying private settings backup: " + error.localizedDescription, isError: true,
                        )
                    }
                }
            } while cloudSyncRequested
        }
    }
}
