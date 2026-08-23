import Foundation

public struct SeedFood: Codable, Equatable, Sendable {
    public var name: String
    public var brand: String?
    public var barcode: String
    public var kilojoulesPer100g: Double
    public var servingGrams: Double?

    public init(name: String, brand: String? = nil, barcode: String, kilojoulesPer100g: Double, servingGrams: Double? = nil) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
    }
}

public enum SeedCatalog: Sendable {
    public static let foods: [SeedFood] = [
        SeedFood(name: "Weet-Bix", brand: "Sanitarium", barcode: "9300652804562", kilojoulesPer100g: 1470, servingGrams: 30),
        SeedFood(name: "Banana", barcode: "4011", kilojoulesPer100g: 371, servingGrams: 118),
        SeedFood(name: "White toast", barcode: "9330001000001", kilojoulesPer100g: 1100, servingGrams: 30),
        SeedFood(name: "Full cream milk", brand: "Generic", barcode: "9330001000002", kilojoulesPer100g: 269, servingGrams: 250),
        SeedFood(name: "Apple", barcode: "4131", kilojoulesPer100g: 218, servingGrams: 150),
        SeedFood(name: "Cheddar cheese", barcode: "9330001000003", kilojoulesPer100g: 1670, servingGrams: 20),
        SeedFood(name: "Yoghurt plain", barcode: "9330001000004", kilojoulesPer100g: 330, servingGrams: 100),
        SeedFood(name: "Vegemite", brand: "Bega", barcode: "9300650123456", kilojoulesPer100g: 800, servingGrams: 5),
    ]
}
