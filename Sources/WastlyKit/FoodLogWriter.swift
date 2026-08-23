import Foundation
import SwiftData

public struct FoodLogDraft: Sendable {
    public var hit: FoodHit
    public var loggedAt: Date
    public var meal: MealSlot
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var note: String

    public init(
        hit: FoodHit,
        loggedAt: Date = .now,
        meal: MealSlot,
        eatenGrams: Double,
        wastedGrams: Double,
        note: String = ""
    ) {
        self.hit = hit
        self.loggedAt = loggedAt
        self.meal = meal
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
        self.note = note
    }
}

public enum FoodLogWriteError: Error, LocalizedError, Sendable {
    case invalidAmount

    public var errorDescription: String? {
        "Eaten and left amounts must be zero or more."
    }
}

public enum FoodLogWriter: Sendable {
    @discardableResult
    public static func save(
        _ draft: FoodLogDraft,
        for child: Child,
        in context: ModelContext
    ) throws -> FoodLog {
        guard draft.eatenGrams.isFinite,
              draft.wastedGrams.isFinite,
              draft.eatenGrams >= 0,
              draft.wastedGrams >= 0
        else {
            throw FoodLogWriteError.invalidAmount
        }

        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = FoodLog(
            loggedAt: draft.loggedAt,
            meal: draft.meal,
            foodName: draft.hit.name,
            brand: draft.hit.brand,
            barcodeRaw: draft.hit.barcodeRaw,
            eatenGrams: draft.eatenGrams,
            wastedGrams: draft.wastedGrams,
            offeredGrams: draft.eatenGrams + draft.wastedGrams,
            kilojoulesPer100g: draft.hit.kilojoulesPer100g,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            origin: draft.hit.origin,
            child: child
        )

        do {
            context.insert(log)
            try context.save()
            return log
        } catch {
            context.rollback()
            throw error
        }
    }
}

public enum LogAmountShortcut: Sendable {
    public static func ateAll(eaten: Double, wasted: Double) -> (eaten: Double, wasted: Double) {
        (max(0, eaten) + max(0, wasted), 0)
    }

    public static func noneEaten(eaten: Double, wasted: Double) -> (eaten: Double, wasted: Double) {
        (0, max(0, eaten) + max(0, wasted))
    }
}
