import Testing
@testable import WastlyKit

struct CatalogSearchTests {
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
