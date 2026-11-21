import Foundation
import Security

/// Named prompt values stored in the host user's Keychain.
public enum PromptSecrets {
    // MARK: Public

    /// Settings needs only account names, also for items created with the security command.
    @concurrent
    public static func names() async throws -> [String] {
        var request = query()
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        try check(status)
        guard let items = result as? [[String: Any]] else {
            throw SessionServiceError("Could not read the secret names from Keychain.")
        }

        return Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Adding refuses collisions. Replacing changes only an existing account.
    @concurrent
    public static func save(name: String, value: String, replacing: Bool) async throws {
        guard replacing || isIdentifier(name) else {
            throw SessionServiceError("Use letters, digits and underscores. Start with a letter or underscore.")
        }
        guard value.isEmpty == false, value.utf8.contains(0) == false else {
            throw SessionServiceError("Enter a non-empty value without a null character.")
        }

        var request = query(name)
        let data = Data(value.utf8)
        if replacing {
            try check(SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary))
        } else {
            request[kSecValueData as String] = data
            try check(SecItemAdd(request as CFDictionary, nil))
        }
    }

    /// Delete just this account from the Sanductor Keychain service.
    @concurrent
    public static func remove(name: String) async throws {
        let status = SecItemDelete(query(name) as CFDictionary)
        if status != errSecItemNotFound {
            try check(status)
        }
    }

    /// A reference ready to copy into a prompt. Older names can contain spaces.
    public static func reference(_ name: String) -> String {
        if isIdentifier(name) {
            "$" + name
        } else {
            "${" + name + "}"
        }
    }

    // MARK: Internal

    /// Only original matches are replaced. Unconfigured shell variables stay literal.
    @concurrent
    static func expand(_ template: String, read: @Sendable (String) throws -> String?) async throws -> String {
        var resolved = [String: String]()
        return try template.replacing(/\$\{([^{}$\r\n]+)\}|\$([A-Za-z_][A-Za-z_0-9]*)/) { match in
            let name = String(match.1 ?? match.2 ?? "")
            if let value = resolved[name] {
                return value
            }
            let value = try read(name)
            if let value {
                resolved[name] = value
                return value
            }
            return String(match.output.0)
        }
    }

    static func read(_ name: String) throws -> String? {
        var request = query(name)
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(request as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            return nil
        }

        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8),
              value.isEmpty == false, value.utf8.contains(0) == false
        else {
            throw SessionServiceError("Replace the API key in Settings → Secrets.")
        }

        return value
    }

    // MARK: Private

    private static func isIdentifier(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z_][A-Za-z_0-9]*/) != nil
    }

    private static func query(_ name: String? = nil) -> [String: Any] {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "SanductorPromptReport",
        ]
        if let name {
            request[kSecAttrAccount as String] = name
        }
        return request
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return

        case errSecDuplicateItem:
            throw SessionServiceError("A secret with that name already exists.")

        case errSecItemNotFound:
            throw SessionServiceError("The secret is missing. Add it in Settings → Secrets.")

        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? String(status)
            throw SessionServiceError("Keychain: " + message)
        }
    }
}
