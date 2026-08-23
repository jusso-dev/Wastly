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

    @Test func gramSplitAndLeftoverMathStayBounded() {
        #expect(GramMath.leftoverGrams(offered: 40, eaten: 30, wasted: 0) == 10)
        #expect(GramMath.leftoverGrams(offered: nil, eaten: 30, wasted: 10) == 10)
        let split = GramMath.split(offered: 20, eaten: 50)
        #expect(split.eaten == 20)
        #expect(split.wasted == 0)
    }

    @Test func barcodeLeadingZerosRemainInTheRawValue() {
        let raw = "09300652804562"
        let log = FoodLog(
            meal: .breakfast,
            foodName: "Weet-Bix",
            barcodeRaw: raw,
            eatenGrams: 30,
            wastedGrams: 0,
            kilojoulesPer100g: 1_470
        )
        #expect(log.barcodeRaw == raw)
        #expect(log.barcodeNormalized == "9300652804562")
        #expect(Barcode.matches(raw, "9300652804562"))
    }

    @Test func backupEncryptionRoundTripsAndRejectsWrongPassword() throws {
        let payload = BackupPayload(
            children: [BackupChild(id: UUID(), firstName: "Sam", dateOfBirth: .now)],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let envelope = try BackupCrypto.seal(
            payload: payload,
            password: "correct-horse"
        )

        #expect(try BackupCrypto.open(
            envelope,
            password: "correct-horse"
        ).children.first?.firstName == "Sam")
        #expect(envelope.plaintextJSON == nil)
        #expect(throws: BackupError.wrongPassword) {
            _ = try BackupCrypto.open(envelope, password: "wrong-password")
        }
    }

    @Test func factInputsHashIsStable() {
        let first = FactTotals(
            days: 2,
            eatenGrams: 100,
            wastedGrams: 10,
            eatenKilojoules: 400,
            wastedKilojoules: 40,
            topFood: "Banana"
        )
        let second = FactTotals(
            days: 2,
            eatenGrams: 100,
            wastedGrams: 10,
            eatenKilojoules: 400,
            wastedKilojoules: 40,
            topFood: "Banana"
        )
        #expect(first.inputsHash == second.inputsHash)
    }

    @Test func outboundFactPayloadAllowsOnlyAggregatesAndOptionalFirstName() throws {
        let payload = try FactTemplates.llmPayload(
            totals: FactTotals(
                days: 3,
                eatenGrams: 200,
                wastedGrams: 40,
                eatenKilojoules: 800,
                wastedKilojoules: 160,
                topFood: "Weet-Bix"
            ),
            firstName: "Sam"
        )
        let object = try payload.jsonObject()
        #expect(Set(object.keys) == [
            "first_name", "days", "eaten_g", "wasted_g", "top_food",
        ])

        let childWeight = try JSONSerialization.data(withJSONObject: [
            "first_name": "Sam",
            "child_metrics": ["weight_kg": 18.0],
        ])
        #expect(throws: PrivacyError.self) {
            try PrivacyGuard.assertFactJSON(childWeight)
        }
    }

    @Test @MainActor func settingsUnitPersistsAndCacheClearKeepsDiary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WastlySettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Wastly.store")
        let logID = UUID()

        do {
            let container = try WastlyContainer.make(url: storeURL)
            let context = ModelContext(container)
            let child = Child(firstName: "Sam", dateOfBirth: .now)
            let settings = SessionStore.settings(in: context)
            #expect(settings.energyUnit == .kilojoules)
            settings.energyUnit = .kilocalories
            let log = FoodLog(
                id: logID,
                meal: .breakfast,
                foodName: "Weet-Bix",
                eatenGrams: 30,
                wastedGrams: 10,
                kilojoulesPer100g: 1_470,
                child: child
            )
            context.insert(child)
            context.insert(log)
            try context.save()

            let store = LocalFoodStore(container: container)
            await store.cacheLookup(FoodHit(
                id: "off:downloaded",
                name: "Downloaded food",
                kilojoulesPer100g: 300,
                origin: .openFoodFacts
            ))
            #expect(Energy.display(log.eatenKilojoules, unit: settings.energyUnit).hasSuffix(" kcal"))
            #expect(try await store.clearCacheLeavingCustomAndLogs() == 1)
        }

        let reopened = try WastlyContainer.make(url: storeURL)
        let context = ModelContext(reopened)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        let log = try #require(logs.first)
        #expect(settings.energyUnit == .kilocalories)
        #expect(logs.map(\.id) == [logID])
        #expect(Energy.display(log.eatenKilojoules, unit: settings.energyUnit).hasSuffix(" kcal"))
        #expect(try context.fetch(FetchDescriptor<FoodCache>()).isEmpty)
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

    @Test @MainActor func firstLaunchOfferCanCancelThenRestoreEncryptedBackup() async throws {
        let childID = UUID()
        let cloud = TestBackupEnvelopeStore()
        let workflow = BackupWorkflow(store: cloud)
        _ = try await workflow.upload(
            payload: BackupPayload(
                children: [BackupChild(id: childID, firstName: "Sam", dateOfBirth: .now)],
                logs: [BackupLog(
                    id: UUID(),
                    childID: childID,
                    loggedAt: .now,
                    meal: .breakfast,
                    foodName: "Weet-Bix",
                    eatenGrams: 30,
                    wastedGrams: 5,
                    kilojoulesPer100g: 1_470
                )],
                customFoods: [],
                energyUnit: .kilojoules
            ),
            password: "restore-password"
        )
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let session = SessionStore(
            container: container,
            backupWorkflow: workflow,
            backupPasswordStore: TestBackupPasswordStore()
        )

        await session.applicationDidBecomeActive()
        #expect(session.backupRestoreOffer?.isFirstLaunch == true)
        #expect(session.backupRestoreOffer?.passwordProtected == true)
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)

        session.cancelRestoreOffer()
        #expect(session.backupRestoreOffer == nil)
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).isEmpty)

        await session.offerRestoreFromICloud()
        #expect(session.backupRestoreOffer != nil)
        let wrongPasswordRestored = await session.restoreFromICloud(
            mode: .replace,
            password: "wrong-password"
        )
        #expect(!wrongPasswordRestored)
        #expect(session.backupPasswordPrompt == nil)
        #expect(session.backupRestoreOffer != nil)
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).isEmpty)

        #expect(await session.restoreFromICloud(
            mode: .replace,
            password: "restore-password"
        ))
        #expect(session.backupRestoreOffer == nil)
        #expect(try context.fetch(FetchDescriptor<Child>()).map(\.id) == [childID])
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).map(\.foodName) == ["Weet-Bix"])
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
