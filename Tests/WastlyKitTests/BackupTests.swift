import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct BackupTests {
    @Test func passwordRoundTrip() throws {
        let password = "correct-horse"
        let payload = BackupPayload(
            children: [BackupChild(id: UUID(), firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let envelope = try BackupCrypto.seal(payload: payload, password: password)
        let opened = try BackupCrypto.open(envelope, password: password)
        #expect(opened.children.first?.firstName == "Sam")
        #expect(envelope.kdfIterations == BackupCrypto.currentKDFIterations)
        #expect(envelope.plaintextJSON == nil)
        #expect(envelope.ciphertext != nil)
        let encodedEnvelope = try JSONEncoder().encode(envelope)
        #expect(!String(decoding: encodedEnvelope, as: UTF8.self).contains(password))
    }

    @Test func wrongPasswordFailsClosed() throws {
        let replacementID = UUID()
        let payload = BackupPayload(
            children: [BackupChild(id: replacementID, firstName: "Cloud child", dateOfBirth: .now)],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let envelope = try BackupCrypto.seal(payload: payload, password: "right")

        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let localChild = Child(firstName: "Local child", dateOfBirth: .now)
        context.insert(localChild)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: "Local Weet-Bix",
            eatenGrams: 30,
            wastedGrams: 0,
            kilojoulesPer100g: 1_470,
            child: localChild
        ))
        try context.save()

        #expect(throws: BackupError.wrongPassword) {
            try BackupRestore.apply(
                envelope: envelope,
                password: "wrong",
                mode: .replace,
                context: context
            )
        }
        let children = try context.fetch(FetchDescriptor<Child>())
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        #expect(children.map(\.id) == [localChild.id])
        #expect(!children.contains { $0.id == replacementID })
        #expect(logs.map(\.foodName) == ["Local Weet-Bix"])
    }

    @Test func versionedCloudEnvelopeRestoresAWeetBixDiary() async throws {
        let sourceContainer = try WastlyContainer.make(inMemory: true)
        let source = ModelContext(sourceContainer)
        let childID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let child = Child(
            id: childID,
            firstName: "Sam",
            dateOfBirth: Date(timeIntervalSince1970: 1_600_000_000),
            photoJPEG: Data([0xFF, 0xD8, 0xFF]),
            createdAt: Date(timeIntervalSince1970: 1_650_000_000)
        )
        let measurement = MeasurementPoint(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            recordedAt: Date(timeIntervalSince1970: 1_710_000_000),
            heightCentimetres: 108,
            weightKilograms: 18.5,
            child: child
        )
        let log = FoodLog(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            loggedAt: Date(timeIntervalSince1970: 1_720_000_000),
            meal: .breakfast,
            foodName: "Weet-Bix",
            brand: "Sanitarium",
            barcodeRaw: "9300652804562",
            eatenGrams: 45,
            wastedGrams: 5,
            offeredGrams: 50,
            kilojoulesPer100g: 1_470,
            note: "With milk",
            origin: .seed,
            child: child
        )
        source.insert(child)
        source.insert(measurement)
        source.insert(log)
        source.insert(FoodCache(
            name: "Family oats",
            brand: "Home",
            barcodeRaw: "12345",
            kilojoulesPer100g: 1_200,
            servingGrams: 35,
            origin: .custom,
            isCustom: true
        ))
        source.insert(FoodCache(
            name: "Remote result",
            kilojoulesPer100g: 900,
            origin: .openFoodFacts
        ))
        let sourceSettings = AppSettings()
        sourceSettings.energyUnit = .kilocalories
        sourceSettings.ocrCloudEnabled = true
        sourceSettings.llmEnabled = true
        sourceSettings.iCloudBackupEnabled = true
        sourceSettings.faceIDEnabled = true
        source.insert(sourceSettings)
        try source.save()

        let payload = try BackupSnapshot.make(in: source)
        #expect(payload.customFoods.map(\.name) == ["Family oats"])

        let cloud = MemoryBackupEnvelopeStore()
        let workflow = BackupWorkflow(store: cloud)
        let backupDate = Date(timeIntervalSince1970: 1_730_000_000)
        let uploaded = try await workflow.upload(payload: payload, createdAt: backupDate)
        let storedMetadata = await cloud.metadata()
        #expect(uploaded.schemaVersion == BackupEnvelope.currentSchemaVersion)
        #expect(storedMetadata?.createdAt == backupDate)
        #expect(storedMetadata?.schemaVersion == BackupEnvelope.currentSchemaVersion)
        let downloaded = try #require(try await workflow.latestEnvelope())

        let targetContainer = try WastlyContainer.make(inMemory: true)
        let target = ModelContext(targetContainer)
        let staleChild = Child(firstName: "Local-only child", dateOfBirth: .now)
        target.insert(staleChild)
        target.insert(FoodLog(
            meal: .dinner,
            foodName: "Local-only log",
            eatenGrams: 1,
            wastedGrams: 0,
            kilojoulesPer100g: 1,
            child: staleChild
        ))
        target.insert(FoodCache(
            name: "Old custom",
            kilojoulesPer100g: 1,
            origin: .custom,
            isCustom: true
        ))
        target.insert(FoodCache(
            name: "Kept download",
            kilojoulesPer100g: 2,
            origin: .usda
        ))
        try target.save()

        try BackupRestore.apply(
            envelope: downloaded,
            password: nil,
            mode: .replace,
            context: target
        )

        let restoredChild = try #require(try target.fetch(FetchDescriptor<Child>()).first)
        #expect(restoredChild.id == childID)
        #expect(restoredChild.firstName == "Sam")
        #expect(restoredChild.photoJPEG == Data([0xFF, 0xD8, 0xFF]))
        #expect(restoredChild.createdAt == Date(timeIntervalSince1970: 1_650_000_000))

        let restoredMeasurement = try #require(try target.fetch(FetchDescriptor<MeasurementPoint>()).first)
        #expect(restoredMeasurement.child?.id == childID)
        #expect(restoredMeasurement.heightCentimetres == 108)
        #expect(restoredMeasurement.weightKilograms == 18.5)

        let restoredLog = try #require(try target.fetch(FetchDescriptor<FoodLog>()).first)
        #expect(restoredLog.child?.id == childID)
        #expect(restoredLog.foodName == "Weet-Bix")
        #expect(restoredLog.brand == "Sanitarium")
        #expect(restoredLog.barcodeRaw == "9300652804562")
        #expect(restoredLog.offeredGrams == 50)
        #expect(restoredLog.note == "With milk")
        #expect(restoredLog.originRaw == FoodOrigin.seed.rawValue)

        let foods = try target.fetch(FetchDescriptor<FoodCache>())
        #expect(foods.filter(\.isCustom).map(\.name) == ["Family oats"])
        #expect(foods.contains { !$0.isCustom && $0.name == "Kept download" })
        #expect(!foods.contains { $0.name == "Remote result" })

        let restoredSettings = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(restoredSettings.energyUnit == .kilocalories)
        #expect(restoredSettings.ocrCloudEnabled)
        #expect(restoredSettings.llmEnabled)
        #expect(restoredSettings.iCloudBackupEnabled)
        #expect(restoredSettings.faceIDEnabled)
        #expect(restoredSettings.lastBackupAt == backupDate)
    }

    @Test func futureSchemaIsRejected() throws {
        let payload = BackupPayload(children: [], logs: [], customFoods: [], energyUnit: .kilojoules)
        var envelope = try BackupCrypto.seal(payload: payload, password: nil)
        envelope.schemaVersion = BackupEnvelope.currentSchemaVersion + 1

        #expect(throws: BackupError.unsupportedSchemaVersion(envelope.schemaVersion)) {
            _ = try BackupCrypto.open(envelope, password: nil)
        }
    }

    @Test func mergeKeepsLocalLogIDsAndAddsOnlyMissingBackupRows() throws {
        let childID = UUID()
        let sharedLogID = UUID()
        let localOnlyLogID = UUID()
        let cloudOnlyLogID = UUID()
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(
            id: childID,
            firstName: "Local Sam",
            dateOfBirth: Date(timeIntervalSince1970: 1_000_000)
        )
        context.insert(child)
        context.insert(FoodLog(
            id: sharedLogID,
            meal: .breakfast,
            foodName: "Local shared row",
            eatenGrams: 20,
            wastedGrams: 1,
            kilojoulesPer100g: 500,
            child: child
        ))
        context.insert(FoodLog(
            id: localOnlyLogID,
            meal: .lunch,
            foodName: "Local only row",
            eatenGrams: 30,
            wastedGrams: 2,
            kilojoulesPer100g: 600,
            child: child
        ))
        try context.save()

        let payload = BackupPayload(
            children: [BackupChild(
                id: childID,
                firstName: "Cloud Sam",
                dateOfBirth: Date(timeIntervalSince1970: 1_000_000)
            )],
            logs: [
                BackupLog(
                    id: sharedLogID,
                    childID: childID,
                    loggedAt: .now,
                    meal: .breakfast,
                    foodName: "Cloud shared row",
                    eatenGrams: 99,
                    wastedGrams: 9,
                    kilojoulesPer100g: 999
                ),
                BackupLog(
                    id: cloudOnlyLogID,
                    childID: childID,
                    loggedAt: .now,
                    meal: .dinner,
                    foodName: "Cloud only row",
                    eatenGrams: 40,
                    wastedGrams: 3,
                    kilojoulesPer100g: 700
                ),
            ],
            customFoods: [],
            energyUnit: .kilojoules
        )

        try BackupRestore.apply(
            payload: payload,
            backupCreatedAt: .now,
            mode: .merge,
            context: context
        )

        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        #expect(logs.count == 3)
        #expect(logs.first { $0.id == sharedLogID }?.foodName == "Local shared row")
        #expect(logs.contains { $0.id == localOnlyLogID })
        #expect(logs.first { $0.id == cloudOnlyLogID }?.foodName == "Cloud only row")
    }

    @Test func duplicateLogIDsAreRejectedBeforeRestoreWrites() throws {
        let childID = UUID()
        let logID = UUID()
        let duplicated = BackupLog(
            id: logID,
            childID: childID,
            loggedAt: .now,
            meal: .snacks,
            foodName: "Duplicate",
            eatenGrams: 10,
            wastedGrams: 0,
            kilojoulesPer100g: 100
        )
        let payload = BackupPayload(
            children: [BackupChild(id: childID, firstName: "Sam", dateOfBirth: .now)],
            logs: [duplicated, duplicated],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let localChild = Child(firstName: "Local child", dateOfBirth: .now)
        context.insert(localChild)
        try context.save()

        #expect(throws: BackupError.missingPayload) {
            try BackupRestore.apply(
                payload: payload,
                backupCreatedAt: .now,
                mode: .merge,
                context: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<Child>()).map(\.id) == [localChild.id])
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).isEmpty)
    }

    @Test func passwordPolicyRequiresEightNonWhitespaceCharacters() {
        #expect(!BackupPasswordPolicy.isValid("short"))
        #expect(!BackupPasswordPolicy.isValid("        "))
        #expect(!BackupPasswordPolicy.isValid("a       "))
        #expect(BackupPasswordPolicy.isValid("long enough"))
    }

    @Test func hostileKDFCostIsRejectedBeforeDerivation() throws {
        let payload = BackupPayload(children: [], logs: [], customFoods: [], energyUnit: .kilojoules)
        var envelope = try BackupCrypto.seal(payload: payload, password: "long-enough")
        envelope.kdfIterations = 50_000_000

        #expect(throws: BackupError.invalidKDFIterations(50_000_000)) {
            _ = try BackupCrypto.open(envelope, password: "long-enough")
        }
    }
}

private actor MemoryBackupEnvelopeStore: BackupEnvelopeStore {
    private var envelopeData: Data?
    private var savedCreatedAt: Date?
    private var savedSchemaVersion: Int?

    func save(envelopeData: Data, createdAt: Date, schemaVersion: Int) async throws {
        self.envelopeData = envelopeData
        self.savedCreatedAt = createdAt
        self.savedSchemaVersion = schemaVersion
    }

    func fetchLatest() async throws -> Data? {
        envelopeData
    }

    func metadata() -> (createdAt: Date, schemaVersion: Int)? {
        guard let savedCreatedAt, let savedSchemaVersion else { return nil }
        return (savedCreatedAt, savedSchemaVersion)
    }
}
