import Foundation
import Testing
@testable import WastlyKit

struct CatalogStoreTests {
    @Test func seedBarcodeWorksOffline() async throws {
        let store = try LocalFoodStore.inMemory()
        await store.insertSeedIfEmpty()
        let hit = await store.barcodeLocal(Barcode.normalized("09300652804562"))
        #expect(hit?.name == "Weet-Bix")
    }

    @Test func upsertDoesNotDuplicate() async throws {
        let store = try LocalFoodStore.inMemory()
        await store.upsertCatalog(SeedCatalog.foods, version: 1)
        await store.upsertCatalog(SeedCatalog.foods, version: 2)
        let first = await store.searchLocal("Weet")
        #expect(first.filter { $0.name == "Weet-Bix" }.count == 1)
    }

    @Test func offlineMissDoesNotCrash() async throws {
        let store = try LocalFoodStore.inMemory()
        let directory = LocalFirstFoodDirectory(store: store)
        let result = await directory.barcode("9999999999999", online: false)
        #expect(result.hits.isEmpty)
        #expect(result.miss == .offline || result.miss == .unknownBarcode)
    }
}
