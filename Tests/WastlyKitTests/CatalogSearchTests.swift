import Testing
@testable import WastlyKit

struct CatalogSearchTests {
    @Test func genericFoodUsesSourceIdentityWithoutInventingABarcode() async throws {
        let store = try LocalFoodStore.inMemory()
        try await store.upsertCatalog(
            [SeedFood(
                name: "Quandong, raw",
                barcode: "",
                kilojoulesPer100g: 259,
                catalogID: "fsanz:F008112"
            )],
            version: 0
        )

        let hit = try #require(await store.searchLocal("quandong").first)
        #expect(hit.id == "catalog:fsanz:f008112")
        #expect(hit.barcodeRaw == nil)
        #expect(hit.origin == .seed)
        #expect(await store.barcodeLocal("8112") == nil)
    }

    @Test func localSearchMatchesMixedCaseNamesAndBrands() async throws {
        let store = try LocalFoodStore.inMemory()
        try await store.upsertCatalog(
            [SeedFood(
                name: "Frozen Peas",
                brand: "McCain",
                barcode: "9300000000012",
                kilojoulesPer100g: 340
            )],
            version: 1
        )

        #expect(await store.searchLocal("mccain").first?.brand == "McCain")
        #expect(await store.searchLocal("FROZEN").first?.name == "Frozen Peas")
    }

    @Test func genericCatalogIDMustBeNamespaced() async throws {
        let store = try LocalFoodStore.inMemory()

        await #expect(throws: CatalogStoreError.invalidFood("catalog ID must be namespaced")) {
            try await store.upsertCatalog(
                [SeedFood(
                    name: "Generic collision",
                    barcode: "",
                    kilojoulesPer100g: 100,
                    catalogID: "8112"
                )],
                version: 1
            )
        }
        #expect(await store.barcodeLocal("8112") == nil)
    }

    @Test func oversizedTextIsRejectedBeforeStorage() async throws {
        let store = try LocalFoodStore.inMemory()
        await #expect(throws: CatalogStoreError.invalidFood("name is too long")) {
            try await store.upsertCatalog(
                [SeedFood(
                    name: String(repeating: "x", count: 201),
                    barcode: "9300000000014",
                    kilojoulesPer100g: 1
                )],
                version: 1
            )
        }
        #expect(await store.catalogSnapshot().rowCount == 0)
    }
}

struct SeedCatalogResourceTests {
    @Test func bundledResourceContainsEveryExpectedOfficialProfile() throws {
        let foods = try SeedCatalog.bundledFoods()

        #expect(foods.count == SeedCatalog.officialFoodCount)
        #expect(Set(foods.compactMap(\.catalogID)).count == SeedCatalog.officialFoodCount)
        #expect(foods.allSatisfy { $0.barcode.isEmpty })
        #expect(foods.allSatisfy { $0.kilojoulesPer100g.isFinite && $0.kilojoulesPer100g >= 0 })
        #expect(foods.contains { $0.name == "Fenugreek seed, dried" })
        #expect(foods.contains { $0.name == "Zucchini, green skin, raw" })
    }
}
