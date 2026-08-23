import Foundation
import CryptoKit
import CommonCrypto
import Security

public struct BackupEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var backupPasswordEnabled: Bool
    public var ciphertext: Data?
    public var plaintextJSON: Data?
    public var salt: Data?
    public var nonce: Data?

    public init(
        schemaVersion: Int = WastlySchema.version,
        createdAt: Date = .now,
        backupPasswordEnabled: Bool,
        ciphertext: Data? = nil,
        plaintextJSON: Data? = nil,
        salt: Data? = nil,
        nonce: Data? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.backupPasswordEnabled = backupPasswordEnabled
        self.ciphertext = ciphertext
        self.plaintextJSON = plaintextJSON
        self.salt = salt
        self.nonce = nonce
    }
}

public struct BackupPayload: Codable, Equatable, Sendable {
    public var children: [BackupChild]
    public var logs: [BackupLog]
    public var customFoods: [SeedFood]
    public var energyUnit: EnergyUnit

    public init(children: [BackupChild], logs: [BackupLog], customFoods: [SeedFood], energyUnit: EnergyUnit) {
        self.children = children
        self.logs = logs
        self.customFoods = customFoods
        self.energyUnit = energyUnit
    }
}

public struct BackupChild: Codable, Equatable, Sendable {
    public var id: UUID
    public var firstName: String
    public var dateOfBirth: Date
}

public struct BackupLog: Codable, Equatable, Sendable {
    public var id: UUID
    public var childID: UUID
    public var loggedAt: Date
    public var meal: MealSlot
    public var foodName: String
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var kilojoulesPer100g: Double
}

public enum BackupCrypto {
    public static func seal(payload: BackupPayload, password: String?) throws -> BackupEnvelope {
        let json = try JSONEncoder().encode(payload)
        guard let password, !password.isEmpty else {
            return BackupEnvelope(backupPasswordEnabled: false, plaintextJSON: json)
        }
        let salt = random(16)
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(json, using: key)
        guard let combined = sealed.combined else { throw BackupError.sealFailed }
        return BackupEnvelope(
            backupPasswordEnabled: true,
            ciphertext: combined,
            salt: salt,
            nonce: Data(sealed.nonce)
        )
    }

    public static func open(_ envelope: BackupEnvelope, password: String?) throws -> BackupPayload {
        if envelope.backupPasswordEnabled {
            guard let password, !password.isEmpty, let salt = envelope.salt, let data = envelope.ciphertext else {
                throw BackupError.wrongPassword
            }
            let key = deriveKey(password: password, salt: salt)
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

    public static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        var derived = Data(count: 32)
        derived.withUnsafeMutableBytes { out in
            password.withCString { pw in
                salt.withUnsafeBytes { saltBuf in
                    _ = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw,
                        password.utf8.count,
                        saltBuf.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(200_000),
                        out.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        return SymmetricKey(data: derived)
    }

    private static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buf in
            _ = SecRandomCopyBytes(kSecRandomDefault, count, buf.baseAddress!)
        }
        return data
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case wrongPassword
    case missingPayload
    case sealFailed
}
