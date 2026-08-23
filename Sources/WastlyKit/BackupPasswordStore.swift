import Foundation
import Security

public protocol BackupPasswordStore: Sendable {
    func save(_ password: String) async throws
    func load() async throws -> String?
    func delete() async throws
}

public enum BackupPasswordPolicy: Sendable {
    public static let minimumLength = 8

    public static func isValid(_ password: String) -> Bool {
        password.count(where: { !$0.isWhitespace }) >= minimumLength
    }
}

public enum BackupPasswordStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidPassword
    case invalidStoredPassword
    case interactionNotAllowed
    case unavailable(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidPassword:
            "Use at least 8 non-space characters for the backup password."
        case .invalidStoredPassword:
            "The saved backup password could not be read. Set it again before backing up."
        case .interactionNotAllowed:
            "Unlock this device, then try the backup password again."
        case .unavailable:
            "The backup password could not be saved securely on this device. Try again."
        }
    }
}

public actor KeychainBackupPasswordStore: BackupPasswordStore {
    private let service: String
    private let account: String

    public init(
        service: String = "au.yumait.Wastly.backup",
        account: String = "envelope-password"
    ) {
        self.service = service
        self.account = account
    }

    public func save(_ password: String) async throws {
        guard BackupPasswordPolicy.isValid(password) else {
            throw BackupPasswordStoreError.invalidPassword
        }
        let data = Data(password.utf8)
        let query = baseQuery()
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw mapped(updateStatus) }
        default:
            throw mapped(addStatus)
        }
    }

    public func load() async throws -> String? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let password = String(data: data, encoding: .utf8),
                  !password.isEmpty
            else {
                throw BackupPasswordStoreError.invalidStoredPassword
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw mapped(status)
        }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mapped(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain] = true
        #endif
        return query
    }

    private func mapped(_ status: OSStatus) -> BackupPasswordStoreError {
        status == errSecInteractionNotAllowed
            ? .interactionNotAllowed
            : .unavailable(status)
    }
}
