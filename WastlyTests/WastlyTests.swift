import Foundation
import SwiftData
import Testing
import WastlyKit
@testable import Wastly

struct WastlyTests {
    @Test func wastedFilterHidesZeroWaste() {
        let wasted = FoodLog(meal: .lunch, foodName: "Toast", eatenGrams: 10, wastedGrams: 5, kilojoulesPer100g: 1000)
        let clean = FoodLog(meal: .lunch, foodName: "Banana", eatenGrams: 80, wastedGrams: 0, kilojoulesPer100g: 370)
        let wastedRows = DiaryDay.filtered([wasted, clean], on: .now, filter: .wasted)
        let eatenRows = DiaryDay.filtered([wasted, clean], on: .now, filter: .eaten)
        #expect(wastedRows.map(\.id) == [wasted.id])
        #expect(eatenRows.map(\.id) == [wasted.id, clean.id])
    }

    @Test func energyLabelUsesHelper() {
        let text = Energy.display(4184, unit: .kilocalories)
        #expect(Energy.kilocalories(fromKilojoules: 4184) == 1000)
        #expect(text.hasSuffix(" kcal"))
        #expect(Energy.display(4184, unit: .kilojoules).hasSuffix(" kJ"))
    }

    @Test func backupPasswordKeychainCanSaveUpdateAndDelete() async throws {
        let store = KeychainBackupPasswordStore(
            service: "au.yumait.Wastly.tests.\(UUID().uuidString)",
            account: "backup-password"
        )
        do {
            #expect(try await store.load() == nil)
            try await store.save("first-password")
            #expect(try await store.load() == "first-password")
            try await store.save("second-password")
            #expect(try await store.load() == "second-password")
            try await store.delete()
            #expect(try await store.load() == nil)
        } catch {
            try? await store.delete()
            throw error
        }
    }

    @Test @MainActor func diaryLockOffNeverRequestsAuthentication() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Child(firstName: "Sam", dateOfBirth: .now))
        context.insert(AppSettings())
        try context.save()
        let authenticator = TestDeviceOwnerAuthenticator(results: [.authenticated])
        let session = SessionStore(
            container: container,
            deviceOwnerAuthenticator: authenticator
        )

        #expect(!session.isLocked)
        await session.applicationDidBecomeActive()
        #expect(!session.isLocked)
        #expect(await authenticator.callCount() == 0)
    }

    @Test @MainActor func diaryLockFailsClosedAndReauthenticatesAfterBackground() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Child(firstName: "Sam", dateOfBirth: .now))
        let settings = AppSettings()
        settings.faceIDEnabled = true
        context.insert(settings)
        try context.save()
        let authenticator = TestDeviceOwnerAuthenticator(results: [
            .authenticated,
            .failed("Authentication failed."),
            .authenticated,
        ])
        let session = SessionStore(
            container: container,
            deviceOwnerAuthenticator: authenticator
        )

        #expect(session.isLocked)
        await session.applicationDidBecomeActive()
        #expect(!session.isLocked)
        #expect(await authenticator.callCount() == 1)

        session.lockForPrivacy()
        await session.applicationDidBecomeActive()
        #expect(session.isLocked)
        #expect(await authenticator.callCount() == 1)

        await session.unlock()
        #expect(session.isLocked)
        #expect(session.lockMessage == "Authentication failed.")

        session.lockForBackground()
        await session.applicationDidBecomeActive()
        #expect(!session.isLocked)
        #expect(await authenticator.callCount() == 3)
    }

    @Test @MainActor func backupPasswordCanBeSetChangedAndRemoved() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: "Weet-Bix",
            eatenGrams: 30,
            wastedGrams: 5,
            kilojoulesPer100g: 1_470,
            child: child
        ))
        let settings = AppSettings()
        settings.iCloudBackupEnabled = true
        context.insert(settings)
        try context.save()

        let cloud = TestBackupEnvelopeStore()
        let workflow = BackupWorkflow(store: cloud)
        let passwords = TestBackupPasswordStore()
        let session = SessionStore(
            container: container,
            backupWorkflow: workflow,
            backupPasswordStore: passwords
        )

        #expect(await session.setBackupPassword("first-password"))
        let firstEnvelope = try #require(try await workflow.latestEnvelope())
        #expect(firstEnvelope.backupPasswordEnabled)
        #expect(try BackupCrypto.open(firstEnvelope, password: "first-password").logs.first?.foodName == "Weet-Bix")
        let firstStoredPassword = await passwords.current()
        #expect(firstStoredPassword == "first-password")

        #expect(await session.setBackupPassword("second-password"))
        let changedEnvelope = try #require(try await workflow.latestEnvelope())
        #expect(throws: BackupError.wrongPassword) {
            _ = try BackupCrypto.open(changedEnvelope, password: "first-password")
        }
        #expect(try BackupCrypto.open(changedEnvelope, password: "second-password").children.first?.firstName == "Sam")
        let changedStoredPassword = await passwords.current()
        #expect(changedStoredPassword == "second-password")

        #expect(await session.removeBackupPassword())
        let unprotectedEnvelope = try #require(try await workflow.latestEnvelope())
        #expect(!unprotectedEnvelope.backupPasswordEnabled)
        #expect(try BackupCrypto.open(unprotectedEnvelope, password: nil).logs.first?.foodName == "Weet-Bix")
        let removedPassword = await passwords.current()
        #expect(removedPassword == nil)
        #expect(!settings.backupPasswordEnabled)

        try await passwords.save("orphan-password")
        await session.backupNow()
        let selfHealedEnvelope = try #require(try await workflow.latestEnvelope())
        #expect(!selfHealedEnvelope.backupPasswordEnabled)
        #expect(await passwords.current() == nil)

        #expect(await session.setBackupPassword("third-password"))
        let protectedEnvelope = try #require(try await workflow.latestEnvelope())
        settings.backupPasswordEnabled = false
        try context.save()
        await session.backupNow()
        #expect(session.backupPasswordPrompt == .change)
        #expect(try await workflow.latestEnvelope() == protectedEnvelope)
    }

    @Test @MainActor func childlessEncryptedRestoreStillSucceeds() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let cloud = TestBackupEnvelopeStore()
        let workflow = BackupWorkflow(store: cloud)
        _ = try await workflow.upload(
            payload: BackupPayload(
                children: [],
                logs: [],
                customFoods: [],
                energyUnit: .kilojoules
            ),
            password: "restore-password"
        )
        let passwords = TestBackupPasswordStore()
        let session = SessionStore(
            container: container,
            backupWorkflow: workflow,
            backupPasswordStore: passwords
        )
        session.backupPasswordPrompt = .restore

        #expect(await session.restoreFromICloud(password: "restore-password"))
        #expect(session.showingOnboarding)
        #expect(session.backupPasswordPrompt == nil)
        #expect(await passwords.current() == "restore-password")
    }

    @Test @MainActor func restoredFaceIDSettingKeepsDiaryLocked() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let cloud = TestBackupEnvelopeStore()
        let workflow = BackupWorkflow(store: cloud)
        _ = try await workflow.upload(payload: BackupPayload(
            children: [BackupChild(id: UUID(), firstName: "Sam", dateOfBirth: .now)],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules,
            settings: BackupSettings(
                energyUnit: .kilojoules,
                ocrCloudEnabled: false,
                llmEnabled: false,
                iCloudBackupEnabled: true,
                backupPasswordEnabled: false,
                faceIDEnabled: true
            )
        ))
        let authenticator = TestDeviceOwnerAuthenticator(results: [.authenticated])
        let session = SessionStore(
            container: container,
            backupWorkflow: workflow,
            backupPasswordStore: TestBackupPasswordStore(),
            deviceOwnerAuthenticator: authenticator
        )

        #expect(await session.restoreFromICloud())
        #expect(session.isLocked)
        #expect(await authenticator.callCount() == 0)
    }
}

private actor TestBackupEnvelopeStore: BackupEnvelopeStore {
    private var data: Data?

    func save(envelopeData: Data, createdAt: Date, schemaVersion: Int) async throws {
        data = envelopeData
    }

    func fetchLatest() async throws -> Data? {
        data
    }
}

private actor TestBackupPasswordStore: BackupPasswordStore {
    private var password: String?

    func save(_ password: String) async throws {
        self.password = password
    }

    func load() async throws -> String? {
        password
    }

    func delete() async throws {
        password = nil
    }

    func current() -> String? {
        password
    }
}

private actor TestDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    private var results: [DeviceOwnerAuthenticationResult]
    private var calls = 0

    init(results: [DeviceOwnerAuthenticationResult]) {
        self.results = results
    }

    func authenticate(localizedReason: String) async -> DeviceOwnerAuthenticationResult {
        calls += 1
        guard !results.isEmpty else {
            return .failed("No test authentication result was configured.")
        }
        return results.removeFirst()
    }

    func callCount() -> Int {
        calls
    }
}
