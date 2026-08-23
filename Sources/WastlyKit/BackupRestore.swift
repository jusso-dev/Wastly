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
        if mode == .replace {
            for child in (try? context.fetch(FetchDescriptor<Child>())) ?? [] {
                context.delete(child)
            }
        }
        var childrenByID: [UUID: Child] = [:]
        for row in payload.children {
            if let existing = ((try? context.fetch(FetchDescriptor<Child>())) ?? []).first(where: { $0.id == row.id }) {
                existing.firstName = row.firstName
                existing.dateOfBirth = row.dateOfBirth
                childrenByID[row.id] = existing
            } else {
                let child = Child(id: row.id, firstName: row.firstName, dateOfBirth: row.dateOfBirth)
                context.insert(child)
                childrenByID[row.id] = child
            }
        }
        let existingLogs = (try? context.fetch(FetchDescriptor<FoodLog>())) ?? []
        let logIDs = Set(existingLogs.map(\.id))
        for row in payload.logs {
            if logIDs.contains(row.id) { continue }
            let log = FoodLog(
                id: row.id,
                loggedAt: row.loggedAt,
                meal: row.meal,
                foodName: row.foodName,
                eatenGrams: row.eatenGrams,
                wastedGrams: row.wastedGrams,
                kilojoulesPer100g: row.kilojoulesPer100g,
                child: childrenByID[row.childID]
            )
            context.insert(log)
        }
        try context.save()
    }
}
