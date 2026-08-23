import Foundation
import LocalAuthentication
import SwiftData
import SwiftUI
import WastlyKit

enum BackupPasswordPromptPurpose: String, Identifiable {
    case set
    case change
    case restore

    var id: String { rawValue }
}

struct BackupRestoreOffer: Equatable, Identifiable {
    let createdAt: Date
    let passwordProtected: Bool
    let isFirstLaunch: Bool

    var id: Date { createdAt }
}

enum DeviceOwnerAuthenticationResult: Equatable, Sendable {
    case authenticated
    case failed(String)
}

protocol DeviceOwnerAuthenticating: Sendable {
    func authenticate(localizedReason: String) async -> DeviceOwnerAuthenticationResult
}

struct LocalDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(localizedReason: String) async -> DeviceOwnerAuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = "Keep Locked"
        context.localizedFallbackTitle = "Use Passcode"

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &availabilityError
        ) else {
            return .failed(Self.message(for: availabilityError))
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: localizedReason
            )
            return authenticated
                ? .authenticated
                : .failed("Face ID or the device passcode did not unlock the diary. Try again.")
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error?) -> String {
        guard let code = (error as? LAError)?.code else {
            return "Device authentication is unavailable. The diary stayed locked."
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return "The diary stayed locked. Tap Unlock when you’re ready."
        case .authenticationFailed:
            return "Face ID or the device passcode did not unlock the diary. Try again."
        case .passcodeNotSet:
            return "Set a device passcode in Settings before turning on the diary lock."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "Face ID or Touch ID is unavailable. Use the device passcode, or check device Settings."
        case .biometryLockout:
            return "Biometrics are locked. Use the device passcode to unlock the diary."
        case .notInteractive:
            return "Unlock while Wastly is onscreen. The diary stayed locked."
        default:
            return "Device authentication failed. The diary stayed locked."
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    let container: ModelContainer
    let store: LocalFoodStore
    let directory: LocalFirstFoodDirectory
    let labelOCR: NutritionLabelOCR
    let plateMatcher: RemotePlateMatcher?
    let factGenerator: RemoteFactGenerator?
    let backupWorkflow: BackupWorkflow
    let backupPasswordStore: any BackupPasswordStore
    let deviceOwnerAuthenticator: any DeviceOwnerAuthenticating

    @Published var selectedChildID: UUID?
    @Published private(set) var isLocked: Bool
    @Published var showingOnboarding: Bool
    @Published var diaryFilter: DiaryLogFilter = .all
    @Published var diaryDay: Date = .now
    @Published var backupMessage: String?
    @Published var backupPasswordPrompt: BackupPasswordPromptPurpose?
    @Published var backupRestoreOffer: BackupRestoreOffer?
    @Published private(set) var authenticationIsRunning = false
    @Published private(set) var lockMessage: String?
    @Published private(set) var backupIsRunning = false
    private var didCheckForRestoreOffer = false
    private var offeredRestoreEnvelope: BackupEnvelope?
    private var automaticallyUnlocksOnNextActive: Bool

    init(
        container: ModelContainer,
        backupWorkflow: BackupWorkflow = BackupWorkflow(store: CloudKitBackupStore()),
        backupPasswordStore: any BackupPasswordStore = KeychainBackupPasswordStore(),
        deviceOwnerAuthenticator: any DeviceOwnerAuthenticating = LocalDeviceOwnerAuthenticator()
    ) {
        self.container = container
        self.store = LocalFoodStore(container: container)
        self.labelOCR = NutritionLabelOCR()
        self.plateMatcher = Self.configuredPlateMatcher()
        self.factGenerator = Self.configuredFactGenerator()
        self.backupWorkflow = backupWorkflow
        self.backupPasswordStore = backupPasswordStore
        self.deviceOwnerAuthenticator = deviceOwnerAuthenticator
        self.directory = LocalFirstFoodDirectory(
            store: store,
            live: RemoteFoodLookup(usdaAPIKey: Self.usdaAPIKey())
        )
        let context = ModelContext(container)
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        let settings = Self.settings(in: context)
        self.selectedChildID = children.sorted { $0.createdAt < $1.createdAt }.first?.id
        self.showingOnboarding = children.isEmpty
        self.isLocked = settings.faceIDEnabled
        self.automaticallyUnlocksOnNextActive = settings.faceIDEnabled
        Task { await store.insertSeedIfEmpty() }
    }

    static func bootstrap() throws -> SessionStore {
        let container = try WastlyContainer.make()
        return SessionStore(container: container)
    }

    private static func usdaAPIKey() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "USDAAPIKey") as? String else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.contains("$("),
              key != "paste-your-data-gov-key-here"
        else { return nil }
        return key
    }

    private static func configuredPlateMatcher() -> RemotePlateMatcher? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "PlateMatchURL") as? String else {
            return nil
        }
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let host = url.host,
              PrivacyAllowlist.isAllowedPlateMatchURL(url, configuredHost: host)
        else { return nil }

        let rawKey = Bundle.main.object(forInfoDictionaryKey: "PlateMatchAPIKey") as? String
        let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String?
        if let trimmedKey,
           !trimmedKey.isEmpty,
           !trimmedKey.contains("$("),
           trimmedKey != "paste-your-plate-matcher-key-here" {
            key = trimmedKey
        } else {
            key = nil
        }
        return RemotePlateMatcher(endpoint: url, apiKey: key)
    }

    private static func configuredFactGenerator() -> RemoteFactGenerator? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "FactServiceURL") as? String else {
            return nil
        }
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let host = url.host,
              PrivacyAllowlist.isAllowedLLMURL(url, configuredHosts: [host])
        else { return nil }

        let rawKey = Bundle.main.object(forInfoDictionaryKey: "FactServiceAPIKey") as? String
        let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String?
        if let trimmedKey,
           !trimmedKey.isEmpty,
           !trimmedKey.contains("$("),
           trimmedKey != "paste-your-fact-service-key-here" {
            key = trimmedKey
        } else {
            key = nil
        }
        return RemoteFactGenerator(endpoint: url, apiKey: key)
    }

    static func settings(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let row = existing.first { return row }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    func diaryLockSettingChanged(enabled: Bool) {
        isLocked = enabled
        automaticallyUnlocksOnNextActive = false
        lockMessage = nil
    }

    func unlock() async {
        guard isLocked, !authenticationIsRunning else { return }
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.faceIDEnabled else {
            isLocked = false
            lockMessage = nil
            return
        }

        authenticationIsRunning = true
        defer { authenticationIsRunning = false }
        switch await deviceOwnerAuthenticator.authenticate(
            localizedReason: "Unlock your private Wastly diary"
        ) {
        case .authenticated:
            isLocked = false
            lockMessage = nil
        case let .failed(message):
            isLocked = true
            lockMessage = message
        }
    }

    func lockForPrivacy() {
        let context = ModelContext(container)
        let enabled = Self.settings(in: context).faceIDEnabled
        isLocked = enabled
        if enabled { lockMessage = nil }
    }

    func lockForBackground() {
        let context = ModelContext(container)
        let enabled = Self.settings(in: context).faceIDEnabled
        isLocked = enabled
        automaticallyUnlocksOnNextActive = enabled
        if enabled { lockMessage = nil }
    }

    func applicationDidBecomeActive() async {
        if automaticallyUnlocksOnNextActive, !authenticationIsRunning {
            automaticallyUnlocksOnNextActive = false
            await unlock()
        }
        guard !isLocked else { return }
        await backupOnActiveIfNeeded()
    }

    func backupOnActiveIfNeeded() async {
        guard !backupIsRunning else { return }
        let context = ModelContext(container)
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        if children.isEmpty, !didCheckForRestoreOffer {
            didCheckForRestoreOffer = true
            await offerRestoreFromICloud(
                isFirstLaunch: true,
                showMissingMessage: false
            )
            if backupRestoreOffer != nil { return }
        }
        guard Self.settings(in: context).iCloudBackupEnabled else { return }
        await backupNow()
    }

    func offerRestoreFromICloud(
        isFirstLaunch: Bool = false,
        showMissingMessage: Bool = true
    ) async {
        guard !backupIsRunning else { return }
        backupIsRunning = true
        defer { backupIsRunning = false }

        do {
            guard let envelope = try await backupWorkflow.latestEnvelope() else {
                offeredRestoreEnvelope = nil
                backupRestoreOffer = nil
                if showMissingMessage { backupMessage = "No iCloud backup was found." }
                return
            }
            offeredRestoreEnvelope = envelope
            backupRestoreOffer = BackupRestoreOffer(
                createdAt: envelope.createdAt,
                passwordProtected: envelope.backupPasswordEnabled,
                isFirstLaunch: isFirstLaunch
            )
            backupMessage = nil
        } catch {
            if isFirstLaunch { didCheckForRestoreOffer = false }
            if showMissingMessage { backupMessage = backupErrorMessage(error) }
        }
    }

    func cancelRestoreOffer() {
        offeredRestoreEnvelope = nil
        backupRestoreOffer = nil
        backupMessage = nil
    }

    func backupNow() async {
        guard !backupIsRunning else { return }
        backupIsRunning = true
        defer { backupIsRunning = false }

        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.iCloudBackupEnabled else {
            backupMessage = "Turn on iCloud backup first."
            return
        }

        do {
            let storedPassword = try await backupPasswordStore.load()
            let password: String?
            if settings.backupPasswordEnabled {
                guard let storedPassword else {
                    backupPasswordPrompt = .set
                    backupMessage = "Enter the backup password again before Wastly can save an encrypted backup."
                    return
                }
                password = storedPassword
            } else {
                if storedPassword != nil {
                    let latestEnvelope = try await backupWorkflow.latestEnvelope()
                    guard latestEnvelope?.backupPasswordEnabled != true else {
                        backupPasswordPrompt = .change
                        backupMessage = "The existing iCloud backup is password-protected. Choose a password before replacing it."
                        return
                    }
                    try await backupPasswordStore.delete()
                }
                password = nil
            }
            let payload = try BackupSnapshot.make(in: context)
            let envelope = try await backupWorkflow.upload(payload: payload, password: password)
            settings.lastBackupAt = envelope.createdAt
            try context.save()
            backupMessage = password == nil
                ? "Backup saved to your private iCloud."
                : "Encrypted backup saved to your private iCloud."
        } catch {
            backupMessage = backupErrorMessage(error)
        }
    }

    @discardableResult
    func setBackupPassword(_ password: String) async -> Bool {
        guard !backupIsRunning else { return false }
        guard BackupPasswordPolicy.isValid(password) else {
            backupMessage = "Use at least 8 non-space characters for the backup password."
            return false
        }

        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.iCloudBackupEnabled else {
            backupMessage = "Turn on iCloud backup first."
            return false
        }

        backupIsRunning = true
        defer { backupIsRunning = false }

        do {
            var payload = try BackupSnapshot.make(in: context)
            if var payloadSettings = payload.settings {
                payloadSettings.backupPasswordEnabled = true
                payload.settings = payloadSettings
            }
            let envelope = try await backupWorkflow.upload(
                payload: payload,
                password: password
            )
            do {
                try await backupPasswordStore.save(password)
            } catch {
                settings.backupPasswordEnabled = true
                settings.lastBackupAt = envelope.createdAt
                try? context.save()
                backupPasswordPrompt = .change
                backupMessage = "The iCloud backup is encrypted, but this iPhone could not save its password. Enter it again."
                return false
            }
            settings.backupPasswordEnabled = true
            settings.lastBackupAt = envelope.createdAt
            try context.save()
            backupPasswordPrompt = nil
            backupMessage = "Backup password saved. A new encrypted backup is in iCloud."
            return true
        } catch {
            backupMessage = backupErrorMessage(error)
            return false
        }
    }

    @discardableResult
    func removeBackupPassword() async -> Bool {
        guard !backupIsRunning else { return false }
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.backupPasswordEnabled else {
            backupMessage = "The iCloud backup does not have a password."
            return true
        }

        backupIsRunning = true
        defer { backupIsRunning = false }

        do {
            var payload = try BackupSnapshot.make(in: context)
            if var payloadSettings = payload.settings {
                payloadSettings.backupPasswordEnabled = false
                payload.settings = payloadSettings
            }
            let envelope = try await backupWorkflow.upload(payload: payload)
            try await backupPasswordStore.delete()
            settings.backupPasswordEnabled = false
            settings.lastBackupAt = envelope.createdAt
            try context.save()
            backupPasswordPrompt = nil
            backupMessage = "Backup password removed. A new unencrypted private backup is in iCloud."
            return true
        } catch {
            backupMessage = "Couldn’t remove the backup password. The local diary is unchanged; try again."
            return false
        }
    }

    @discardableResult
    func restoreFromICloud(
        mode: RestoreMode = .replace,
        password: String? = nil,
        showMissingMessage: Bool = true
    ) async -> Bool {
        guard !backupIsRunning else { return false }
        backupIsRunning = true
        defer { backupIsRunning = false }

        do {
            let envelope: BackupEnvelope?
            if let offeredRestoreEnvelope {
                envelope = offeredRestoreEnvelope
            } else {
                envelope = try await backupWorkflow.latestEnvelope()
            }
            guard let envelope else {
                if showMissingMessage {
                    backupMessage = "No iCloud backup was found."
                }
                return false
            }
            let restorePassword: String?
            if envelope.backupPasswordEnabled {
                if let password {
                    restorePassword = password
                } else {
                    restorePassword = try await backupPasswordStore.load()
                }
                guard restorePassword != nil else {
                    if backupRestoreOffer == nil {
                        backupPasswordPrompt = .restore
                    }
                    backupMessage = "Enter the password used to protect this iCloud backup."
                    return false
                }
            } else {
                restorePassword = nil
            }

            let payload = try await Task.detached(priority: .userInitiated) {
                try BackupCrypto.open(envelope, password: restorePassword)
            }.value
            let context = ModelContext(container)
            try BackupRestore.apply(
                payload: payload,
                backupCreatedAt: envelope.createdAt,
                mode: mode,
                context: context
            )
            let children = try context.fetch(FetchDescriptor<Child>())
                .sorted { $0.createdAt < $1.createdAt }
            selectedChildID = children.first?.id
            showingOnboarding = children.isEmpty
            diaryLockSettingChanged(enabled: Self.settings(in: context).faceIDEnabled)
            offeredRestoreEnvelope = nil
            backupRestoreOffer = nil
            if let restorePassword {
                do {
                    try await backupPasswordStore.save(restorePassword)
                    backupPasswordPrompt = nil
                } catch {
                    backupPasswordPrompt = .change
                    backupMessage = "Backup restored, but its password could not be saved on this iPhone. Enter it again."
                    return true
                }
            } else {
                do {
                    try await backupPasswordStore.delete()
                    backupPasswordPrompt = nil
                } catch {
                    backupPasswordPrompt = nil
                    backupMessage = "Backup restored, but an old password could not be cleared from this iPhone. Unlock it, then restore again to finish cleanup."
                    return true
                }
            }
            if children.isEmpty {
                backupMessage = "The iCloud backup did not contain a child profile."
            } else {
                backupMessage = mode == .merge
                    ? "Backup merged with this iPhone’s diary."
                    : "Backup restored from your private iCloud."
            }
            return true
        } catch BackupError.wrongPassword {
            if backupRestoreOffer == nil {
                backupPasswordPrompt = .restore
            }
            backupMessage = "That password did not unlock the backup. Your local diary is unchanged."
            return false
        } catch {
            if showMissingMessage { backupMessage = backupErrorMessage(error) }
            return false
        }
    }

    private func backupErrorMessage(_ error: Error) -> String {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            return description
        }
        return "iCloud backup is unavailable. Your local diary is unchanged."
    }
}
