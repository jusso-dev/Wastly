import Foundation
import SwiftData

public enum RestoreMode: Sendable {
    case replace
    case merge
}

public enum BackupRestore {
    /// Wrong password throws and does not mutate the store.
    public static func apply(
        envelope: BackupEnvelope,
        password: String?,
        mode: RestoreMode,
        context: ModelContext
    ) throws {
        let payload = try BackupCrypto.open(envelope, password: password)
        let childIDs = Set(payload.children.map(\.id))
        guard childIDs.count == payload.children.count,
              payload.logs.allSatisfy({ childIDs.contains($0.childID) }),
              payload.measurements.allSatisfy({ childIDs.contains($0.childID) })
        else {
            throw BackupError.missingPayload
        }

        do {
            let existingChildren = try context.fetch(FetchDescriptor<Child>())
            let backupChildren = Dictionary(uniqueKeysWithValues: payload.children.map { ($0.id, $0) })
            var childrenByID: [UUID: Child] = [:]
            for child in existingChildren {
                if let row = backupChildren[child.id] {
                    child.firstName = row.firstName
                    child.dateOfBirth = row.dateOfBirth
                    child.photoJPEG = row.photoJPEG
                    child.createdAt = row.createdAt ?? envelope.createdAt
                    childrenByID[child.id] = child
                } else if mode == .replace {
                    context.delete(child)
                }
            }
            for row in payload.children where childrenByID[row.id] == nil {
                let child = Child(
                    id: row.id,
                    firstName: row.firstName,
                    dateOfBirth: row.dateOfBirth,
                    photoJPEG: row.photoJPEG,
                    createdAt: row.createdAt ?? envelope.createdAt
                )
                context.insert(child)
                childrenByID[row.id] = child
            }

            let existingMeasurements = try context.fetch(FetchDescriptor<MeasurementPoint>())
            if mode == .replace {
                for measurement in existingMeasurements { context.delete(measurement) }
            }
            let measurementIDs = mode == .replace ? [] : Set(existingMeasurements.map(\.id))
            for row in payload.measurements where !measurementIDs.contains(row.id) {
                context.insert(MeasurementPoint(
                    id: row.id,
                    recordedAt: row.recordedAt,
                    heightCentimetres: row.heightCentimetres,
                    weightKilograms: row.weightKilograms,
                    child: childrenByID[row.childID]
                ))
            }

            let existingLogs = try context.fetch(FetchDescriptor<FoodLog>())
            if mode == .replace {
                for log in existingLogs { context.delete(log) }
                for fact in try context.fetch(FetchDescriptor<FunFact>()) { context.delete(fact) }
            }
            let logIDs = mode == .replace ? [] : Set(existingLogs.map(\.id))
            for row in payload.logs where !logIDs.contains(row.id) {
                context.insert(FoodLog(
                    id: row.id,
                    loggedAt: row.loggedAt,
                    meal: row.meal,
                    foodName: row.foodName,
                    brand: row.brand,
                    barcodeRaw: row.barcodeRaw,
                    eatenGrams: row.eatenGrams,
                    wastedGrams: row.wastedGrams,
                    offeredGrams: row.offeredGrams,
                    kilojoulesPer100g: row.kilojoulesPer100g,
                    note: row.note,
                    origin: row.origin ?? .custom,
                    child: childrenByID[row.childID]
                ))
            }

            var existingCustomFoods = try context.fetch(FetchDescriptor<FoodCache>())
                .filter(\.isCustom)
            if mode == .replace {
                for food in existingCustomFoods { context.delete(food) }
                existingCustomFoods = []
            }
            for row in payload.customFoods {
                let barcode = row.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
                let existing = existingCustomFoods.first {
                    (!barcode.isEmpty && $0.barcodeNormalized == Barcode.normalized(barcode))
                        || ($0.name.caseInsensitiveCompare(row.name) == .orderedSame
                            && ($0.brand ?? "").caseInsensitiveCompare(row.brand ?? "") == .orderedSame)
                }
                if let existing {
                    existing.name = row.name
                    existing.brand = row.brand
                    existing.barcodeRaw = barcode.isEmpty ? nil : barcode
                    existing.barcodeNormalized = barcode.isEmpty ? nil : Barcode.normalized(barcode)
                    existing.kilojoulesPer100g = row.kilojoulesPer100g
                    existing.servingGrams = row.servingGrams
                } else {
                    context.insert(FoodCache(
                        name: row.name,
                        brand: row.brand,
                        barcodeRaw: barcode.isEmpty ? nil : barcode,
                        kilojoulesPer100g: row.kilojoulesPer100g,
                        servingGrams: row.servingGrams,
                        origin: .custom,
                        isCustom: true
                    ))
                }
            }

            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? {
                let created = AppSettings()
                context.insert(created)
                return created
            }()
            let restoredSettings = payload.settings
            settings.energyUnit = restoredSettings?.energyUnit ?? payload.energyUnit
            if let restoredSettings {
                settings.ocrCloudEnabled = restoredSettings.ocrCloudEnabled
                settings.llmEnabled = restoredSettings.llmEnabled
                settings.iCloudBackupEnabled = restoredSettings.iCloudBackupEnabled
                settings.backupPasswordEnabled = restoredSettings.backupPasswordEnabled
                settings.faceIDEnabled = restoredSettings.faceIDEnabled
            }
            settings.lastBackupAt = envelope.createdAt

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
