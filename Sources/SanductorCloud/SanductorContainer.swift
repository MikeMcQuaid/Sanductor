import CloudKit

// MARK: - SanductorContainer

/// Only open CloudKit when the app signature names its container.
struct SanductorContainer {
    // MARK: Lifecycle

    init?(bundleIdentifier: String?) {
        guard let bundleIdentifier else {
            return nil
        }

        identifier = "iCloud." + bundleIdentifier
        guard let environmentName = Self.signedEnvironment(for: identifier) else {
            return nil
        }

        environment = environmentName
    }

    // MARK: Internal

    let environment: String

    var container: CKContainer {
        CKContainer(identifier: identifier)
    }

    // MARK: Private

    private let identifier: String

    #if !os(macOS)
        /// The iPhone target always carries its CloudKit entitlement.
        private static func signedEnvironment(for _: String) -> String? {
            ""
        }
    #endif
}
