import CloudKit
import Foundation

public protocol BackupEnvelopeStore: Sendable {
    func save(
        envelopeData: Data,
        createdAt: Date,
        schemaVersion: Int
    ) async throws
    func fetchLatest() async throws -> Data?
}

public enum BackupCloudError: Error, LocalizedError, Sendable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case quotaExceeded
    case retryLater(TimeInterval?)
    case invalidRecord
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .noAccount:
            "Sign in to iCloud to use backup. Your local diary is unchanged."
        case .restricted:
            "iCloud is restricted on this device. Your local diary is unchanged."
        case .temporarilyUnavailable, .retryLater, .unavailable:
            "iCloud backup is temporarily unavailable. Wastly will try again next time it opens."
        case .quotaExceeded:
            "Your iCloud storage is full. Free some space, then try backup again."
        case .invalidRecord:
            "The iCloud backup could not be read. Your local diary is unchanged."
        }
    }
}

public actor BackupWorkflow {
    private let store: any BackupEnvelopeStore

    public init(store: any BackupEnvelopeStore) {
        self.store = store
    }

    @discardableResult
    public func upload(
        payload: BackupPayload,
        password: String? = nil,
        createdAt: Date = .now
    ) async throws -> BackupEnvelope {
        let envelope = try BackupCrypto.seal(
            payload: payload,
            password: password,
            createdAt: createdAt
        )
        let data = try JSONEncoder().encode(envelope)
        try await store.save(
            envelopeData: data,
            createdAt: envelope.createdAt,
            schemaVersion: envelope.schemaVersion
        )
        return envelope
    }

    public func latestEnvelope() async throws -> BackupEnvelope? {
        guard let data = try await store.fetchLatest() else { return nil }
        do {
            return try JSONDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupCloudError.invalidRecord
        }
    }
}

public actor CloudKitBackupStore: BackupEnvelopeStore {
    private static let zoneID = CKRecordZone.ID(zoneName: "WastlyBackupZone")
    private static let recordID = CKRecord.ID(
        recordName: "current-backup",
        zoneID: zoneID
    )

    private let container: CKContainer
    private let database: CKDatabase

    public init(containerIdentifier: String? = nil) {
        let container = containerIdentifier.map(CKContainer.init(identifier:)) ?? .default()
        self.container = container
        self.database = container.privateCloudDatabase
    }

    public func save(
        envelopeData: Data,
        createdAt: Date,
        schemaVersion: Int
    ) async throws {
        try await requireAvailableAccount()
        try await ensureZone()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WastlyBackup-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("backup-envelope.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try envelopeData.write(to: fileURL, options: .atomic)

        let record: CKRecord
        do {
            record = try await database.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            record = CKRecord(recordType: "WastlyBackup", recordID: Self.recordID)
        } catch {
            throw map(error)
        }
        configure(
            record,
            fileURL: fileURL,
            createdAt: createdAt,
            schemaVersion: schemaVersion
        )

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let server = error.serverRecord else { throw map(error) }
            configure(
                server,
                fileURL: fileURL,
                createdAt: createdAt,
                schemaVersion: schemaVersion
            )
            do {
                _ = try await database.save(server)
            } catch {
                throw map(error)
            }
        } catch let error as CKError where error.code == .userDeletedZone || error.code == .zoneNotFound {
            try await createZone()
            let retry = CKRecord(recordType: "WastlyBackup", recordID: Self.recordID)
            configure(
                retry,
                fileURL: fileURL,
                createdAt: createdAt,
                schemaVersion: schemaVersion
            )
            do {
                _ = try await database.save(retry)
            } catch {
                throw map(error)
            }
        } catch {
            throw map(error)
        }
    }

    public func fetchLatest() async throws -> Data? {
        try await requireAvailableAccount()
        let record: CKRecord
        do {
            record = try await database.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        } catch {
            throw map(error)
        }
        guard let asset = record["envelope"] as? CKAsset,
              let fileURL = asset.fileURL
        else {
            throw BackupCloudError.invalidRecord
        }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw BackupCloudError.invalidRecord
        }
    }

    private func requireAvailableAccount() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            throw map(error)
        }
        switch status {
        case .available:
            return
        case .noAccount:
            throw BackupCloudError.noAccount
        case .restricted:
            throw BackupCloudError.restricted
        case .temporarilyUnavailable:
            throw BackupCloudError.temporarilyUnavailable
        case .couldNotDetermine:
            throw BackupCloudError.unavailable
        @unknown default:
            throw BackupCloudError.unavailable
        }
    }

    private func ensureZone() async throws {
        do {
            _ = try await database.recordZone(for: Self.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try await createZone()
        } catch {
            throw map(error)
        }
    }

    private func createZone() async throws {
        do {
            _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
        } catch {
            throw map(error)
        }
    }

    private func configure(
        _ record: CKRecord,
        fileURL: URL,
        createdAt: Date,
        schemaVersion: Int
    ) {
        record["envelope"] = CKAsset(fileURL: fileURL)
        record["createdAt"] = createdAt as CKRecordValue
        record["schemaVersion"] = NSNumber(value: schemaVersion)
    }

    private func map(_ error: Error) -> BackupCloudError {
        if let cloudError = error as? BackupCloudError { return cloudError }
        guard let error = error as? CKError else { return .unavailable }
        switch error.code {
        case .notAuthenticated:
            return .noAccount
        case .permissionFailure:
            return .restricted
        case .networkFailure, .networkUnavailable:
            return .temporarilyUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return .retryLater(error.retryAfterSeconds)
        default:
            return .unavailable
        }
    }
}
