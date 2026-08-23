import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct FoodLogWriterTests {
    @Test func customAndRecentFoodsSaveWithoutAConnection() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        try context.save()
        let custom = FoodHit(
            id: "custom:toast",
            name: "Toast",
            kilojoulesPer100g: 1_000,
            origin: .custom
        )
        let recent = FoodHit(
            id: "recent:apple",
            name: "Apple",
            brand: "Local orchard",
            barcodeRaw: "01234567",
            kilojoulesPer100g: 218,
            origin: .recent
        )

        try FoodLogWriter.save(
            FoodLogDraft(
                hit: custom,
                loggedAt: Date(timeIntervalSince1970: 1_700_000_000),
                meal: .breakfast,
                eatenGrams: 30,
                wastedGrams: 10,
                note: "  Toasted  "
            ),
            for: child,
            in: context
        )
        try FoodLogWriter.save(
            FoodLogDraft(
                hit: recent,
                loggedAt: Date(timeIntervalSince1970: 1_700_000_100),
                meal: .snacks,
                eatenGrams: 0,
                wastedGrams: 80
            ),
            for: child,
            in: context
        )

        let logs = try context.fetch(FetchDescriptor<FoodLog>(sortBy: [SortDescriptor(\.loggedAt)]))
        #expect(logs.count == 2)
        #expect(logs[0].foodName == "Toast")
        #expect(logs[0].offeredGrams == 40)
        #expect(logs[0].note == "Toasted")
        #expect(logs[1].foodName == "Apple")
        #expect(logs[1].eatenGrams == 0)
        #expect(logs[1].wastedGrams == 80)
        #expect(logs[1].barcodeNormalized == "1234567")
    }

    @Test func amountShortcutsPreserveTheOfferedTotal() {
        let ateAll = LogAmountShortcut.ateAll(eaten: 30, wasted: 10)
        #expect(ateAll.eaten == 40)
        #expect(ateAll.wasted == 0)

        let noneEaten = LogAmountShortcut.noneEaten(eaten: 30, wasted: 10)
        #expect(noneEaten.eaten == 0)
        #expect(noneEaten.wasted == 40)
    }

    @Test func invalidAmountDoesNotInsertALog() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        try context.save()

        #expect(throws: FoodLogWriteError.self) {
            try FoodLogWriter.save(
                FoodLogDraft(
                    hit: FoodHit(
                        id: "custom:test",
                        name: "Test",
                        kilojoulesPer100g: 0,
                        origin: .custom
                    ),
                    meal: .other,
                    eatenGrams: -5,
                    wastedGrams: 0
                ),
                for: child,
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).isEmpty)
    }
}
