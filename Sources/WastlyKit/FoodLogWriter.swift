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
    case childUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Eaten and left amounts must be zero or more, with a valid total."
        case .childUnavailable:
            "The selected child is no longer available. Choose a child and try again."
        }
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
        let offeredGrams = draft.eatenGrams + draft.wastedGrams
        guard offeredGrams.isFinite else {
            throw FoodLogWriteError.invalidAmount
        }

        // Keep this write isolated from unsaved edits owned by the caller's context.
        let writeContext = ModelContext(context.container)
        let childID = child.id
        let childDescriptor = FetchDescriptor<Child>(
            predicate: #Predicate { $0.id == childID }
        )
        guard let persistedChild = try writeContext.fetch(childDescriptor).first else {
            throw FoodLogWriteError.childUnavailable
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
            offeredGrams: offeredGrams,
            kilojoulesPer100g: draft.hit.kilojoulesPer100g,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            origin: draft.hit.origin,
            child: persistedChild
        )

        do {
            writeContext.insert(log)
            try writeContext.save()
            return log
        } catch {
            writeContext.rollback()
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
