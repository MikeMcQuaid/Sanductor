import Foundation
import SanductorDomain

public extension SessionService {
    /// Publishes the sidebar projection without exposing the host's metadata file.
    func publishSidebar(_ repositories: [SidebarRepository]) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: paths.sanductorDirectory, withIntermediateDirectories: true)
            var data = try JSONEncoder().encode(repositories)
            data.append(UInt8(ascii: "\n"))
            try data.write(
                to: URL(filePath: paths.sanductorDirectory + "/sidebar-"
                    + (WorkspacePaths.isProductionBuild ? "sanductor" : "sanductor-dev") + ".json"),
                options: .atomic,
            )
            return true
        } catch {
            return false
        }
    }
}
