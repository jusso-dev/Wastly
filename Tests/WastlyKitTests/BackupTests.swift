import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct BackupTests {
    @Test func passwordRoundTrip() throws {
        let payload = BackupPayload(
            children: [BackupChild(id: UUID(), firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))],
            logs: [],
            customFoods: [],
            energyUnit: .kilojoules
        )
        let envelope = try BackupCrypto.seal(payload: payload, password: "correct-horse")
        let opened = try BackupCrypto.open(envelope, password: "correct-horse")
        #expect(opened.children.first?.firstName == "Sam")
    }

    @Test func wrongPasswordFailsClosed() throws {
        let payload = BackupPayload(children: [], logs: [], customFoods: [], energyUnit: .kilojoules)
        let envelope = try BackupCrypto.seal(payload: payload, password: "right")
        #expect(throws: BackupError.wrongPassword) {
            _ = try BackupCrypto.open(envelope, password: "wrong")
        }
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
