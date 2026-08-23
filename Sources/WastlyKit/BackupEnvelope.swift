import Foundation
import CryptoKit
import CommonCrypto
import Security
import SwiftData

public struct BackupEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Date
    public var backupPasswordEnabled: Bool
    public var ciphertext: Data?
    public var plaintextJSON: Data?
    public var salt: Data?
    public var nonce: Data?
    public var kdfIterations: Int?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAt: Date = .now,
        backupPasswordEnabled: Bool,
        ciphertext: Data? = nil,
        plaintextJSON: Data? = nil,
        salt: Data? = nil,
        nonce: Data? = nil,
        kdfIterations: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.backupPasswordEnabled = backupPasswordEnabled
        self.ciphertext = ciphertext
        self.plaintextJSON = plaintextJSON
        self.salt = salt
        self.nonce = nonce
        self.kdfIterations = kdfIterations
    }
}

public struct BackupPayload: Codable, Equatable, Sendable {
    public var children: [BackupChild]
    public var measurements: [BackupMeasurement]
    public var logs: [BackupLog]
    public var customFoods: [SeedFood]
    public var energyUnit: EnergyUnit
    public var settings: BackupSettings?

    public init(
        children: [BackupChild],
        measurements: [BackupMeasurement] = [],
        logs: [BackupLog],
        customFoods: [SeedFood],
        energyUnit: EnergyUnit,
        settings: BackupSettings? = nil
    ) {
        self.children = children
        self.measurements = measurements
        self.logs = logs
        self.customFoods = customFoods
        self.energyUnit = energyUnit
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case children
        case measurements
        case logs
        case customFoods
        case energyUnit
        case settings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        children = try container.decode([BackupChild].self, forKey: .children)
        measurements = try container.decodeIfPresent([BackupMeasurement].self, forKey: .measurements) ?? []
        logs = try container.decode([BackupLog].self, forKey: .logs)
        customFoods = try container.decode([SeedFood].self, forKey: .customFoods)
        energyUnit = try container.decode(EnergyUnit.self, forKey: .energyUnit)
        settings = try container.decodeIfPresent(BackupSettings.self, forKey: .settings)
    }
}

public struct BackupChild: Codable, Equatable, Sendable {
    public var id: UUID
    public var firstName: String
    public var dateOfBirth: Date
    public var photoJPEG: Data?
    public var createdAt: Date?

    public init(
        id: UUID,
        firstName: String,
        dateOfBirth: Date,
        photoJPEG: Data? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.dateOfBirth = dateOfBirth
        self.photoJPEG = photoJPEG
        self.createdAt = createdAt
    }
}

public struct BackupMeasurement: Codable, Equatable, Sendable {
    public var id: UUID
    public var childID: UUID
    public var recordedAt: Date
    public var heightCentimetres: Double?
    public var weightKilograms: Double?

    public init(
        id: UUID,
        childID: UUID,
        recordedAt: Date,
        heightCentimetres: Double?,
        weightKilograms: Double?
    ) {
        self.id = id
        self.childID = childID
        self.recordedAt = recordedAt
        self.heightCentimetres = heightCentimetres
        self.weightKilograms = weightKilograms
    }
}

public struct BackupLog: Codable, Equatable, Sendable {
    public var id: UUID
    public var childID: UUID
    public var loggedAt: Date
    public var meal: MealSlot
    public var foodName: String
    public var brand: String?
    public var barcodeRaw: String?
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var offeredGrams: Double?
    public var kilojoulesPer100g: Double
    public var note: String?
    public var origin: FoodOrigin?

    public init(
        id: UUID,
        childID: UUID,
        loggedAt: Date,
        meal: MealSlot,
        foodName: String,
        brand: String? = nil,
        barcodeRaw: String? = nil,
        eatenGrams: Double,
        wastedGrams: Double,
        offeredGrams: Double? = nil,
        kilojoulesPer100g: Double,
        note: String? = nil,
        origin: FoodOrigin? = nil
    ) {
        self.id = id
        self.childID = childID
        self.loggedAt = loggedAt
        self.meal = meal
        self.foodName = foodName
        self.brand = brand
        self.barcodeRaw = barcodeRaw
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
        self.offeredGrams = offeredGrams
        self.kilojoulesPer100g = kilojoulesPer100g
        self.note = note
        self.origin = origin
    }
}

public struct BackupSettings: Codable, Equatable, Sendable {
    public var energyUnit: EnergyUnit
    public var ocrCloudEnabled: Bool
    public var llmEnabled: Bool
    public var iCloudBackupEnabled: Bool
    public var backupPasswordEnabled: Bool
    public var faceIDEnabled: Bool

    public init(
        energyUnit: EnergyUnit,
        ocrCloudEnabled: Bool,
        llmEnabled: Bool,
        iCloudBackupEnabled: Bool,
        backupPasswordEnabled: Bool,
        faceIDEnabled: Bool
    ) {
        self.energyUnit = energyUnit
        self.ocrCloudEnabled = ocrCloudEnabled
        self.llmEnabled = llmEnabled
        self.iCloudBackupEnabled = iCloudBackupEnabled
        self.backupPasswordEnabled = backupPasswordEnabled
        self.faceIDEnabled = faceIDEnabled
    }
}

public enum BackupSnapshot: Sendable {
    public static func make(in context: ModelContext) throws -> BackupPayload {
        let children = try context.fetch(FetchDescriptor<Child>())
        let measurements = try context.fetch(FetchDescriptor<MeasurementPoint>())
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        let customFoods = try context.fetch(FetchDescriptor<FoodCache>()).filter(\.isCustom)
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first

        return BackupPayload(
            children: children.map {
                BackupChild(
                    id: $0.id,
                    firstName: $0.firstName,
                    dateOfBirth: $0.dateOfBirth,
                    photoJPEG: $0.photoJPEG,
                    createdAt: $0.createdAt
                )
            },
            measurements: measurements.compactMap { measurement in
                guard let childID = measurement.child?.id else { return nil }
                return BackupMeasurement(
                    id: measurement.id,
                    childID: childID,
                    recordedAt: measurement.recordedAt,
                    heightCentimetres: measurement.heightCentimetres,
                    weightKilograms: measurement.weightKilograms
                )
            },
            logs: logs.compactMap { log in
                guard let childID = log.child?.id else { return nil }
                return BackupLog(
                    id: log.id,
                    childID: childID,
                    loggedAt: log.loggedAt,
                    meal: log.meal,
                    foodName: log.foodName,
                    brand: log.brand,
                    barcodeRaw: log.barcodeRaw,
                    eatenGrams: log.eatenGrams,
                    wastedGrams: log.wastedGrams,
                    offeredGrams: log.offeredGrams,
                    kilojoulesPer100g: log.kilojoulesPer100g,
                    note: log.note,
                    origin: FoodOrigin(rawValue: log.originRaw)
                )
            },
            customFoods: customFoods.map {
                SeedFood(
                    name: $0.name,
                    brand: $0.brand,
                    barcode: $0.barcodeRaw ?? "",
                    kilojoulesPer100g: $0.kilojoulesPer100g,
                    servingGrams: $0.servingGrams
                )
            },
            energyUnit: settings?.energyUnit ?? .kilojoules,
            settings: settings.map {
                BackupSettings(
                    energyUnit: $0.energyUnit,
                    ocrCloudEnabled: $0.ocrCloudEnabled,
                    llmEnabled: $0.llmEnabled,
                    iCloudBackupEnabled: $0.iCloudBackupEnabled,
                    backupPasswordEnabled: $0.backupPasswordEnabled,
                    faceIDEnabled: $0.faceIDEnabled
                )
            }
        )
    }
}

public enum BackupCrypto {
    public static let currentKDFIterations = 600_000
    public static let legacyKDFIterations = 200_000

    public static func seal(
        payload: BackupPayload,
        password: String?,
        createdAt: Date = .now
    ) throws -> BackupEnvelope {
        let json = try JSONEncoder().encode(payload)
        guard let password, !password.isEmpty else {
            return BackupEnvelope(
                createdAt: createdAt,
                backupPasswordEnabled: false,
                plaintextJSON: json
            )
        }
        let salt = try random(16)
        let key = try deriveKey(
            password: password,
            salt: salt,
            iterations: currentKDFIterations
        )
        let sealed = try AES.GCM.seal(json, using: key)
        guard let combined = sealed.combined else { throw BackupError.sealFailed }
        return BackupEnvelope(
            createdAt: createdAt,
            backupPasswordEnabled: true,
            ciphertext: combined,
            salt: salt,
            nonce: Data(sealed.nonce),
            kdfIterations: currentKDFIterations
        )
    }

    public static func open(_ envelope: BackupEnvelope, password: String?) throws -> BackupPayload {
        guard (1...BackupEnvelope.currentSchemaVersion).contains(envelope.schemaVersion) else {
            throw BackupError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        if envelope.backupPasswordEnabled {
            guard let password, !password.isEmpty, let salt = envelope.salt, let data = envelope.ciphertext else {
                throw BackupError.wrongPassword
            }
            let iterations = envelope.kdfIterations ?? legacyKDFIterations
            guard (100_000...2_000_000).contains(iterations) else {
                throw BackupError.invalidKDFIterations(iterations)
            }
            let key = try deriveKey(
                password: password,
                salt: salt,
                iterations: iterations
            )
            do {
                let box = try AES.GCM.SealedBox(combined: data)
                let json = try AES.GCM.open(box, using: key)
                return try JSONDecoder().decode(BackupPayload.self, from: json)
            } catch {
                throw BackupError.wrongPassword
            }
        }
        guard let json = envelope.plaintextJSON else { throw BackupError.missingPayload }
        return try JSONDecoder().decode(BackupPayload.self, from: json)
    }

    public static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int = currentKDFIterations
    ) throws -> SymmetricKey {
        guard (100_000...2_000_000).contains(iterations) else {
            throw BackupError.invalidKDFIterations(iterations)
        }
        var derived = Data(count: 32)
        let status: Int32 = derived.withUnsafeMutableBytes { out in
            password.withCString { pw in
                salt.withUnsafeBytes { saltBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw,
                        password.utf8.count,
                        saltBuf.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        out.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.keyDerivationFailed(status)
        }
        return SymmetricKey(data: derived)
    }

    private static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, count, buf.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BackupError.randomGenerationFailed(status)
        }
        return data
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case wrongPassword
    case missingPayload
    case sealFailed
    case unsupportedSchemaVersion(Int)
    case invalidKDFIterations(Int)
    case keyDerivationFailed(Int32)
    case randomGenerationFailed(OSStatus)
}
