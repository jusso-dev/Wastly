import SwiftData
import Testing
@testable import WastlyKit

struct BarcodeTests {
    @Test func stripsLeadingZerosForMatchingOnly() {
        #expect(Barcode.normalized("0009300652804562") == "9300652804562")
        #expect(Barcode.matches("0004011", "4011"))
    }

    @Test func unknownDoesNotMatch() {
        #expect(Barcode.matches("4011", "4131") == false)
        #expect(Barcode.normalized("0000").isEmpty)
    }

    @Test func preservesMeaningOfPaddedCode() {
        #expect(Barcode.matches("09300652804562", "9300652804562"))
    }

    @Test func leadingZerosRemainInRawPersistentFields() throws {
        let raw = "09300652804562"
        let normalized = "9300652804562"
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: "Weet-Bix",
            barcodeRaw: raw,
            eatenGrams: 30,
            wastedGrams: 0,
            kilojoulesPer100g: 1_470
        ))
        context.insert(FoodCache(
            name: "Weet-Bix",
            barcodeRaw: raw,
            kilojoulesPer100g: 1_470,
            origin: .openFoodFacts
        ))
        context.insert(CatalogFood(
            barcodeRaw: raw,
            name: "Weet-Bix",
            kilojoulesPer100g: 1_470,
            catalogVersion: 1
        ))
        try context.save()

        let log = try #require(context.fetch(FetchDescriptor<FoodLog>()).first)
        let cache = try #require(context.fetch(FetchDescriptor<FoodCache>()).first)
        let catalog = try #require(context.fetch(FetchDescriptor<CatalogFood>()).first)
        #expect(log.barcodeRaw == raw)
        #expect(cache.barcodeRaw == raw)
        #expect(catalog.barcodeRaw == raw)
        #expect(log.barcodeNormalized == normalized)
        #expect(cache.barcodeNormalized == normalized)
        #expect(catalog.barcodeNormalized == normalized)
    }
}
