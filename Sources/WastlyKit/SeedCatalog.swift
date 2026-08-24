import Foundation

public struct SeedFood: Codable, Equatable, Sendable {
    public var catalogID: String?
    public var name: String
    public var brand: String?
    public var barcode: String
    public var kilojoulesPer100g: Double
    public var servingGrams: Double?

    public init(
        name: String,
        brand: String? = nil,
        barcode: String,
        kilojoulesPer100g: Double,
        servingGrams: Double? = nil,
        catalogID: String? = nil
    ) {
        self.catalogID = catalogID
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.kilojoulesPer100g = kilojoulesPer100g
        self.servingGrams = servingGrams
    }

    var catalogKey: String {
        let sourceID = catalogID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sourceID.isEmpty ? Barcode.normalized(barcode) : sourceID.lowercased()
    }
}

public enum SeedCatalog: Sendable {
    public static let bundleVersion = 1
    public static let officialFoodCount = 4_128
    public static let sourceSummary = "AUSNUT 2023 + AFCD Release 3"
    public static let licenceURL = URL(
        string: "https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement"
    )!
    public static let limitationStatement = "There are limitations associated with food composition databases. "
        + "Food composition data used in the database or databases may represent an average of the nutrient content "
        + "of a particular sample of foods and ingredients, determined at a particular time. The nutrient composition "
        + "of foods and ingredients can vary substantially between batches and brands because of a number of factors, "
        + "including changes in season, processing practices and ingredient source, and methods of calculation."
    public static let territoryNotice = "This catalogue is based on Australian data, which may not be appropriate "
        + "for use in other countries."

    static let storageVersion = -bundleVersion
    static let bundleSentinelKey = "fsanz:f000050"

    private static let legacyFoods: [SeedFood] = [
        SeedFood(name: "Weet-Bix", brand: "Sanitarium", barcode: "9300652804562", kilojoulesPer100g: 1470, servingGrams: 30),
        SeedFood(name: "Banana", barcode: "4011", kilojoulesPer100g: 371, servingGrams: 118),
        SeedFood(name: "White toast", barcode: "9330001000001", kilojoulesPer100g: 1100, servingGrams: 30),
        SeedFood(name: "Full cream milk", brand: "Generic", barcode: "9330001000002", kilojoulesPer100g: 269, servingGrams: 250),
        SeedFood(name: "Apple", barcode: "4131", kilojoulesPer100g: 218, servingGrams: 150),
        SeedFood(name: "Cheddar cheese", barcode: "9330001000003", kilojoulesPer100g: 1670, servingGrams: 20),
        SeedFood(name: "Yoghurt plain", barcode: "9330001000004", kilojoulesPer100g: 330, servingGrams: 100),
        SeedFood(name: "Vegemite", brand: "Bega", barcode: "9300650123456", kilojoulesPer100g: 800, servingGrams: 5),
    ]

    private static let bundledResult: Result<[SeedFood], SeedCatalogError> = {
        do {
            guard let url = Bundle.module.url(forResource: "seed-foods", withExtension: "json") else {
                throw SeedCatalogError.missingResource
            }
            let payload = try JSONDecoder().decode(
                BundledCatalogFile.self,
                from: Data(contentsOf: url)
            )
            guard payload.metadata.version == bundleVersion else {
                throw SeedCatalogError.invalidVersion(payload.metadata.version)
            }
            guard payload.foods.count == officialFoodCount else {
                throw SeedCatalogError.invalidCount(payload.foods.count)
            }
            guard Set(payload.foods.map(\.catalogKey)).count == payload.foods.count,
                  payload.foods.allSatisfy({ !$0.catalogKey.isEmpty }) else {
                throw SeedCatalogError.invalidIdentifiers
            }
            return .success(payload.foods)
        } catch let error as SeedCatalogError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }()

    public static let foods: [SeedFood] = legacyFoods + ((try? bundledFoods()) ?? [])

    public static func bundledFoods() throws -> [SeedFood] {
        try bundledResult.get()
    }
}

public enum SeedCatalogError: Error, Equatable, LocalizedError, Sendable {
    case missingResource
    case unreadable(String)
    case invalidVersion(Int)
    case invalidCount(Int)
    case invalidIdentifiers

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            "The bundled food catalogue is missing."
        case let .unreadable(message):
            "The bundled food catalogue could not be read: \(message)"
        case let .invalidVersion(version):
            "The bundled food catalogue has unsupported version \(version)."
        case let .invalidCount(count):
            "The bundled food catalogue has an unexpected \(count.formatted()) rows."
        case .invalidIdentifiers:
            "The bundled food catalogue contains missing or duplicate identifiers."
        }
    }
}

private struct BundledCatalogFile: Decodable {
    struct Metadata: Decodable {
        var version: Int
    }

    var metadata: Metadata
    var foods: [SeedFood]
}
