import CloudKit
import Foundation

/// One settings archive in the signed-in user's private database.
public struct PrivateSettingsCloud: Sendable {
    // MARK: Lifecycle

    public init?() {
        guard let entitled = SanductorContainer(bundleIdentifier: Bundle.main.bundleIdentifier) else {
            return nil
        }

        cloud = entitled
    }

    // MARK: Public

    @preconcurrency
    @MainActor
    public func synchronise(
        merge: (Data?, String) throws -> Data, saved: (Data, String) -> Void,
    ) async throws -> Bool {
        let container = cloud.container
        guard try await container.accountStatus() == .available else {
            return false
        }

        let database = container.privateCloudDatabase
        let account = try await cloud.environment + "." + container.userRecordID().recordName
        let id = CKRecord.ID(recordName: "private-settings")
        let record: CKRecord
        do {
            let existing = try await database.record(for: id)
            guard existing.recordType == "PrivateSettings", existing["archive"] is Data else {
                throw CocoaError(.fileReadCorruptFile)
            }

            record = existing
        } catch CKError.unknownItem {
            record = CKRecord(recordType: "PrivateSettings", recordID: id)
        }

        let remote = record["archive"] as? Data
        let archive = try merge(remote, account)
        if archive != remote {
            record["archive"] = archive
            let (results, _) = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged,
            )
            for result in results.values {
                _ = try result.get()
            }
        }
        saved(archive, account)
        return true
    }

    // MARK: Private

    private let cloud: SanductorContainer
}
