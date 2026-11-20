#if os(macOS)
    import Security

    extension SanductorContainer {
        static func signedEnvironment(for identifier: String) -> String? {
            guard let task = SecTaskCreateFromSelf(nil),
                  let allowed = SecTaskCopyValueForEntitlement(
                      task, "com.apple.developer.icloud-container-identifiers" as CFString, nil,
                  ) as? [String], allowed.contains(identifier)
            else {
                return nil
            }

            return SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-container-environment" as CFString, nil,
            ) as? String ?? "Development"
        }
    }
#endif
