import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct RecentsCacheTests {
    @Test func anOnlineLogBecomesAnOfflineRecent() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let store = LocalFoodStore(container: container)
        let weetBix = FoodHit(
            id: "off:09300652804562",
            name: "Weet-Bix",
            brand: "Sanitarium",
            barcodeRaw: "09300652804562",
            kilojoulesPer100g: 1_470,
            origin: .openFoodFacts
        )
        let directory = LocalFirstFoodDirectory(
            store: store,
            live: SingleFoodLookup(hit: weetBix)
        )

        let online = await directory.barcode("9300652804562", online: true)
        let hit = try #require(online.hits.first)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        try context.save()
        try FoodLogWriter.save(
            FoodLogDraft(
                hit: hit,
                meal: .breakfast,
                eatenGrams: 30,
                wastedGrams: 10
            ),
            for: child,
            in: context
        )
        await directory.remember(hit)

        let offline = await directory.barcode("09300652804562", online: false)
        #expect(offline.hits.first?.name == "Weet-Bix")
        #expect(offline.miss == nil)
        let cached = try #require(
            ModelContext(container).fetch(FetchDescriptor<FoodCache>()).first
        )
        #expect(cached.useCount == 1)
        #expect(cached.lastUsedAt > .distantPast)
    }

    @Test func mostUsedThenMostRecentFoodsSearchFirst() async throws {
        let store = try LocalFoodStore.inMemory()
        let first = FoodHit(
            id: "custom:first",
            name: "First food",
            kilojoulesPer100g: 100,
            origin: .custom
        )
        let favourite = FoodHit(
            id: "custom:favourite",
            name: "Favourite food",
            kilojoulesPer100g: 200,
            origin: .custom
        )
        await store.touchRecent(first)
        await store.touchRecent(favourite)
        await store.touchRecent(favourite)

        let hits = await store.searchLocal("food")

        #expect(hits.map(\.id) == ["custom:favourite", "custom:first"])
    }

    @Test func clearingCachePreservesCustomFoodsAndDiaryLogs() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let store = LocalFoodStore(container: container)
        await store.cacheLookup(FoodHit(
            id: "off:downloaded",
            name: "Downloaded food",
            kilojoulesPer100g: 300,
            origin: .openFoodFacts
        ))
        await store.saveCustom(FoodHit(
            id: "custom:toast",
            name: "Toast",
            kilojoulesPer100g: 1_000,
            origin: .custom
        ))
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: "Downloaded food",
            eatenGrams: 20,
            wastedGrams: 5,
            kilojoulesPer100g: 300,
            child: child
        ))
        try context.save()

        let removed = try await store.clearCacheLeavingCustomAndLogs()

        #expect(removed == 1)
        let verificationContext = ModelContext(container)
        let remainingFoods = try verificationContext.fetch(FetchDescriptor<FoodCache>())
        #expect(remainingFoods.count == 1)
        #expect(remainingFoods.first?.isCustom == true)
        #expect(remainingFoods.first?.name == "Toast")
        #expect(try verificationContext.fetch(FetchDescriptor<FoodLog>()).count == 1)
    }

    @Test func customFoodEnergyIsOptionalAndUsesTheDisplayUnit() throws {
        let gramsOnly = try CustomFoodBuilder.make(
            name: "  Family toast  ",
            energyPer100gText: "",
            unit: .kilojoules
        )
        #expect(gramsOnly.name == "Family toast")
        #expect(gramsOnly.kilojoulesPer100g == 0)

        let calories = try CustomFoodBuilder.make(
            name: "Muesli",
            energyPer100gText: "100",
            unit: .kilocalories,
            servingGramsText: "30"
        )
        #expect(abs(calories.kilojoulesPer100g - 418.4) < 0.001)
        #expect(calories.servingGrams == 30)

        #expect(throws: CustomFoodInputError.invalidEnergy) {
            try CustomFoodBuilder.make(
                name: "Muesli",
                energyPer100gText: "not a number",
                unit: .kilojoules
            )
        }
        #expect(throws: CustomFoodInputError.invalidServing) {
            try CustomFoodBuilder.make(
                name: "Muesli",
                energyPer100gText: "100",
                unit: .kilojoules,
                servingGramsText: "0"
            )
        }
    }
}

private struct SingleFoodLookup: LiveFoodLookup {
    var hit: FoodHit

    func search(_ query: String) async -> [FoodHit] {
        [hit]
    }

    func barcode(_ code: String) async -> FoodHit? {
        hit
    }
}
