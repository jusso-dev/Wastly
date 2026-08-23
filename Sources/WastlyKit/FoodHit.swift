import Foundation

public struct FoodHit: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var brand: String?
    public var barcodeRaw: String?
    public var kilojoulesPer100g: Double
    public var servingGrams: Double?
    public var origin: FoodOrigin

    public var barcodeNormalized: String? {
        barcodeRaw.map(Barcode.normalized)
    }

    public init(
        id: String,
        name: String,
        brand: String? = nil,
        barcodeRaw: String? = nil,
        kilojoulesPer100g: Double,
        servingGrams: Double? = nil,
        origin: FoodOrigin
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcodeRaw = barcodeRaw
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
        self.origin = origin
    }
}

public enum FoodLookupMiss: Equatable, Sendable {
    case offline
    case unknownBarcode
    case emptyQuery
}

public struct FoodLookupResult: Equatable, Sendable {
    public var hits: [FoodHit]
    public var miss: FoodLookupMiss?

    public init(hits: [FoodHit], miss: FoodLookupMiss? = nil) {
        self.hits = hits
        self.miss = miss
    }
}
