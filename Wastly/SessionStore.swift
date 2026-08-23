import Foundation
import LocalAuthentication
import SwiftData
import SwiftUI
import WastlyKit

@MainActor
final class SessionStore: ObservableObject {
    let container: ModelContainer
    let store: LocalFoodStore
    let directory: LocalFirstFoodDirectory
    let labelOCR: NutritionLabelOCR
    let plateMatcher: RemotePlateMatcher?
    let factGenerator: RemoteFactGenerator?
    let backupWorkflow: BackupWorkflow

    @Published var selectedChildID: UUID?
    @Published var isLocked: Bool
    @Published var showingOnboarding: Bool
    @Published var diaryFilter: DiaryLogFilter = .all
    @Published var diaryDay: Date = .now
    @Published var backupMessage: String?
    @Published private(set) var backupIsRunning = false
    private var didAttemptAutomaticRestore = false

    init(container: ModelContainer) {
        self.container = container
        self.store = LocalFoodStore(container: container)
        self.labelOCR = NutritionLabelOCR()
        self.plateMatcher = Self.configuredPlateMatcher()
        self.factGenerator = Self.configuredFactGenerator()
        self.backupWorkflow = BackupWorkflow(store: CloudKitBackupStore())
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

    func refreshLockFromSettings() {
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        if !settings.faceIDEnabled {
            isLocked = false
        }
    }

    func unlock() async {
        let context = ModelContext(container)
        let settings = Self.settings(in: context)
        guard settings.faceIDEnabled else {
            isLocked = false
            return
        }
        let auth = LAContext()
        var error: NSError?
        guard auth.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = true
            return
        }
        do {
            let ok = try await auth.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock the Wastly diary"
            )
            isLocked = !ok
        } catch {
            isLocked = true
        }
    }

    func lockIfNeeded() {
        let context = ModelContext(container)
        isLocked = Self.settings(in: context).faceIDEnabled
    }

    func backupOnActiveIfNeeded() async {
        guard !backupIsRunning else { return }
        let context = ModelContext(container)
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        if children.isEmpty, !didAttemptAutomaticRestore {
            didAttemptAutomaticRestore = true
            let restored = await restoreFromICloud(showMissingMessage: false)
            if restored { return }
        }
        guard Self.settings(in: context).iCloudBackupEnabled else { return }
        await backupNow()
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
        guard !settings.backupPasswordEnabled else {
            backupMessage = "Password-protected iCloud backup needs a password before it can run."
            return
        }

        do {
            let payload = try BackupSnapshot.make(in: context)
            let envelope = try await backupWorkflow.upload(payload: payload)
            settings.lastBackupAt = envelope.createdAt
            try context.save()
            backupMessage = "Backup saved to your private iCloud."
        } catch {
            backupMessage = backupErrorMessage(error)
        }
    }

    @discardableResult
    func restoreFromICloud(showMissingMessage: Bool = true) async -> Bool {
        guard !backupIsRunning else { return false }
        backupIsRunning = true
        defer { backupIsRunning = false }

        do {
            guard let envelope = try await backupWorkflow.latestEnvelope() else {
                if showMissingMessage {
                    backupMessage = "No iCloud backup was found."
                }
                return false
            }
            let context = ModelContext(container)
            try BackupRestore.apply(
                envelope: envelope,
                password: nil,
                mode: .replace,
                context: context
            )
            let children = try context.fetch(FetchDescriptor<Child>())
                .sorted { $0.createdAt < $1.createdAt }
            selectedChildID = children.first?.id
            showingOnboarding = children.isEmpty
            isLocked = false
            backupMessage = children.isEmpty
                ? "The iCloud backup did not contain a child profile."
                : "Backup restored from your private iCloud."
            return !children.isEmpty
        } catch BackupError.wrongPassword {
            backupMessage = "This iCloud backup needs its password before it can be restored."
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
