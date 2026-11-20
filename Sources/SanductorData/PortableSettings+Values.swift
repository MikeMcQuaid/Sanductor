import Foundation
import SanductorDomain

extension PortableSettings {
    /// Bridge Codable preferences to the native dictionaries, dates and arrays of the XML file.
    static func plist(_ value: some Encodable) throws -> NSObject {
        let data = try PropertyListEncoder().encode(value)
        let decoded = try unsafe PropertyListSerialization.propertyList(from: data, format: nil)
        guard let result = decoded as? NSObject else {
            throw SessionServiceError("Cannot encode settings.plist")
        }

        return result
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: NSObject) throws -> T {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        return try PropertyListDecoder().decode(type, from: data)
    }

    static func portableValues(_ values: [String: NSObject]) throws -> [String: NSObject] {
        guard let data = values["workMode"] as? Data else {
            return values
        }

        var portable = values
        let mode = try JSONDecoder().decode(WorkMode.self, from: data)
        portable["workMode"] = try plist(mode)
        return portable
    }
}
