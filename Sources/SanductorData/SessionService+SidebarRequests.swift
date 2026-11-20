import Darwin
import Foundation
import SanductorDomain

public extension SessionService {
    /// Watches the shared request directory; idle work is a directory event.
    func sidebarRequests() -> AsyncStream<[(id: String, request: SidebarRequest)]> {
        let directory = sidebarRequestsDirectory
        return AsyncStream { continuation in
            let task = Task {
                let wake = Self.directoryChanges(in: directory)
                var seen = Set<String>()
                while Task.isCancelled == false {
                    let requests = Self.readSidebarRequests(in: directory).filter { seen.contains($0.id) == false }
                    if requests.isEmpty == false {
                        seen.formUnion(requests.map(\.id))
                        continuation.yield(requests)
                    }
                    if let wake {
                        await wake.wait(timeout: .seconds(RefreshCadence.occludedPollSeconds))
                    } else {
                        // No directory watcher could be installed; use the existing safety cadence.
                        try? await Task.sleep(for: .seconds(RefreshCadence.occludedPollSeconds))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Publishes the acknowledgement only after the host has handled the request.
    func answerSidebarRequest(id: String, response: SidebarResponse) {
        guard UUID(uuidString: id) != nil else {
            return
        }

        let folder = unsafe open(sidebarRequestsDirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard folder >= 0 else {
            return
        }

        defer { close(folder) }
        do {
            try SandboxFile.replace(id + ".response", in: folder, with: JSONEncoder().encode(response), mode: 0o644)
            _ = unsafe unlinkat(folder, id + ".request", 0)
        } catch {
            PerformanceLog.recordMessage("Could not write the shared request reply.", isError: true)
        }
    }

    // MARK: Internal

    internal var sidebarRequestsDirectory: String {
        paths.sanductorDirectory + "/sidebar-requests-"
            + (WorkspacePaths.isProductionBuild ? "sanductor" : "sanductor-dev")
    }

    internal static func readSidebarRequests(in directory: String) -> [(id: String, request: SidebarRequest)] {
        let folder = unsafe open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard folder >= 0 else {
            return []
        }

        defer { close(folder) }
        let manager = FileManager.default
        return ((try? manager.contentsOfDirectory(atPath: directory)) ?? []).sorted().compactMap { name in
            guard name.hasSuffix(".request") else {
                return nil
            }

            let id = String(name.dropLast(".request".count))
            guard UUID(uuidString: id) != nil,
                  manager.fileExists(atPath: directory + "/" + id + ".response") == false,
                  let data = try? SandboxFile.read(name, byteLimit: SidebarRequest.maximumBytes, relativeTo: folder),
                  let request = try? JSONDecoder().decode(SidebarRequest.self, from: data)
            else {
                return nil
            }

            return (id, request)
        }
    }
}
