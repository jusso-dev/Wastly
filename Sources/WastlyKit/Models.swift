import Foundation
import SwiftData

/// Schema version 1. Future versions should use lightweight migration stages for additive changes.
public enum WastlySchema: VersionedSchema {
    public static let version = 1
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Child.self,
            MeasurementPoint.self,
            FoodLog.self,
            FoodCache.self,
            CatalogFood.self,
            FunFact.self,
            AppSettings.self,
            CatalogState.self,
        ]
    }
}

public enum WastlyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WastlySchema.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum MealSlot: String, Codable, Sendable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snacks
    case other
}

public enum FoodOrigin: String, Codable, Sendable {
    case custom
    case recent
    case openFoodFacts
    case usda
    case catalog
    case seed
    case cloudPlate
}

@Model
public final class Child {
    @Attribute(.unique) public var id: UUID
    public var firstName: String
    public var dateOfBirth: Date
    public var photoJPEG: Data?
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \FoodLog.child)
    public var logs: [FoodLog]
    @Relationship(deleteRule: .cascade, inverse: \MeasurementPoint.child)
    public var measurements: [MeasurementPoint]
    @Relationship(deleteRule: .cascade, inverse: \FunFact.child)
    public var facts: [FunFact]

    public init(
        id: UUID = UUID(),
        firstName: String,
        dateOfBirth: Date,
        photoJPEG: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.firstName = firstName
        self.dateOfBirth = dateOfBirth
        self.photoJPEG = photoJPEG
        self.createdAt = createdAt
        self.logs = []
        self.measurements = []
        self.facts = []
    }
}

@Model
public final class MeasurementPoint {
    @Attribute(.unique) public var id: UUID
    public var recordedAt: Date
    public var heightCentimetres: Double?
    public var weightKilograms: Double?
    public var child: Child?

    public init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        heightCentimetres: Double? = nil,
        weightKilograms: Double? = nil,
        child: Child? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.heightCentimetres = heightCentimetres
        self.weightKilograms = weightKilograms
        self.child = child
    }
}

@Model
public final class FoodLog {
    @Attribute(.unique) public var id: UUID
    public var loggedAt: Date
    public var mealRaw: String
    public var foodName: String
    public var brand: String?
    public var barcodeRaw: String?
    public var barcodeNormalized: String?
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var offeredGrams: Double?
    public var kilojoulesPer100g: Double
    public var note: String?
    public var originRaw: String
    public var child: Child?

    public var meal: MealSlot {
        get { MealSlot(rawValue: mealRaw) ?? .other }
        set { mealRaw = newValue.rawValue }
    }

    public var eatenKilojoules: Double {
        Energy.energyKilojoules(grams: eatenGrams, kilojoulesPer100g: kilojoulesPer100g)
    }

    public var wastedKilojoules: Double {
        Energy.energyKilojoules(grams: wastedGrams, kilojoulesPer100g: kilojoulesPer100g)
    }

    public init(
        id: UUID = UUID(),
        loggedAt: Date = .now,
        meal: MealSlot,
        foodName: String,
        brand: String? = nil,
        barcodeRaw: String? = nil,
        eatenGrams: Double,
        wastedGrams: Double,
        offeredGrams: Double? = nil,
        kilojoulesPer100g: Double,
        note: String? = nil,
        origin: FoodOrigin = .custom,
        child: Child? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.mealRaw = meal.rawValue
        self.foodName = foodName
        self.brand = brand
        self.barcodeRaw = barcodeRaw
        self.barcodeNormalized = barcodeRaw.map(Barcode.normalized)
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
        self.offeredGrams = offeredGrams
        self.kilojoulesPer100g = kilojoulesPer100g
        self.note = note
        self.originRaw = origin.rawValue
        self.child = child
    }
}

@Model
public final class FoodCache {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var brand: String?
    public var barcodeRaw: String?
    public var barcodeNormalized: String?
    public var kilojoulesPer100g: Double
    public var servingGrams: Double?
    public var originRaw: String
    public var isCustom: Bool
    public var useCount: Int
    public var lastUsedAt: Date
    public var providerKey: String?

    public init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcodeRaw: String? = nil,
        kilojoulesPer100g: Double,
        servingGrams: Double? = nil,
        origin: FoodOrigin,
        isCustom: Bool = false,
        useCount: Int = 0,
        lastUsedAt: Date = .distantPast,
        providerKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcodeRaw = barcodeRaw
        self.barcodeNormalized = barcodeRaw.map(Barcode.normalized)
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
        self.originRaw = origin.rawValue
        self.isCustom = isCustom
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.providerKey = providerKey
    }
}

@Model
public final class CatalogFood {
    // `barcodeNormalized` is uniquely indexed; this second index backs local name search.
    #Index<CatalogFood>([\.name])

    @Attribute(.unique) public var barcodeNormalized: String
    public var name: String
    public var brand: String?
    public var barcodeRaw: String
    public var kilojoulesPer100g: Double
    public var servingGrams: Double?
    public var catalogVersion: Int
    public var updatedAt: Date

    public init(
        barcodeRaw: String,
        name: String,
        brand: String? = nil,
        kilojoulesPer100g: Double,
        servingGrams: Double? = nil,
        catalogVersion: Int,
        updatedAt: Date = .now
    ) {
        self.barcodeRaw = barcodeRaw
        self.barcodeNormalized = Barcode.normalized(barcodeRaw)
        self.name = name
        self.brand = brand
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
        self.catalogVersion = catalogVersion
        self.updatedAt = updatedAt
    }
}

@Model
public final class FunFact {
    @Attribute(.unique) public var id: UUID
    public var text: String
    public var inputsHash: String
    public var createdAt: Date
    public var child: Child?

    public init(
        id: UUID = UUID(),
        text: String,
        inputsHash: String,
        createdAt: Date = .now,
        child: Child? = nil
    ) {
        self.id = id
        self.text = text
        self.inputsHash = inputsHash
        self.createdAt = createdAt
        self.child = child
    }
}

@Model
public final class AppSettings {
    @Attribute(.unique) public var id: String
    public var energyUnitRaw: String
    public var ocrCloudEnabled: Bool
    public var llmEnabled: Bool
    public var iCloudBackupEnabled: Bool
    public var backupPasswordEnabled: Bool
    public var faceIDEnabled: Bool
    public var lastBackupAt: Date?
    public var lastCatalogSyncAt: Date?
    public var catalogBytesOnDisk: Int

    public var energyUnit: EnergyUnit {
        get { EnergyUnit(rawValue: energyUnitRaw) ?? .kilojoules }
        set { energyUnitRaw = newValue.rawValue }
    }

    public init() {
        self.id = "singleton"
        self.energyUnitRaw = EnergyUnit.kilojoules.rawValue
        self.ocrCloudEnabled = false
        self.llmEnabled = false
        self.iCloudBackupEnabled = false
        self.backupPasswordEnabled = false
        self.faceIDEnabled = false
        self.lastBackupAt = nil
        self.lastCatalogSyncAt = nil
        self.catalogBytesOnDisk = 0
    }
}

@Model
public final class CatalogState {
    @Attribute(.unique) public var id: String
    public var catalogVersion: Int
    public var etag: String?
    public var lastSuccessAt: Date?
    public var lastError: String?

    public init() {
        self.id = "singleton"
        self.catalogVersion = 0
        self.etag = nil
        self.lastSuccessAt = nil
        self.lastError = nil
    }
}
