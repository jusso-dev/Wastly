import Foundation
import SwiftData

public protocol FoodDirectory: Sendable {
    func search(_ query: String, online: Bool) async -> FoodLookupResult
    func barcode(_ code: String, online: Bool) async -> FoodLookupResult
    func remember(_ hit: FoodHit) async
    func saveCustom(_ hit: FoodHit) async
}

/// Recents and custom first, then local catalog/seed, then live OFF/USDA on a miss.
public actor LocalFirstFoodDirectory: FoodDirectory {
    private let store: LocalFoodStore
    private let live: LiveFoodLookup?

    public init(store: LocalFoodStore, live: LiveFoodLookup? = nil) {
        self.store = store
        self.live = live
    }

    public func search(_ query: String, online: Bool) async -> FoodLookupResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return FoodLookupResult(hits: [], miss: .emptyQuery)
        }
        let localHits = await store.searchLocal(trimmed)
        guard online, let live else {
            return FoodLookupResult(
                hits: localHits,
                miss: localHits.isEmpty ? .offline : nil
            )
        }
        let remoteHits = await live.search(trimmed)
        for hit in remoteHits { await store.cacheLookup(hit) }
        let hits = FoodHitIdentity.merged(localHits + remoteHits)
        return FoodLookupResult(hits: hits, miss: hits.isEmpty ? .unknownBarcode : nil)
    }

    public func barcode(_ code: String, online: Bool) async -> FoodLookupResult {
        let key = Barcode.normalized(code)
        guard !key.isEmpty else {
            return FoodLookupResult(hits: [], miss: .unknownBarcode)
        }
        if let hit = await store.barcodeLocal(key) {
            return FoodLookupResult(hits: [hit])
        }
        if online, let live {
            if let hit = await live.barcode(code) {
                await store.cacheLookup(hit)
                return FoodLookupResult(hits: [hit])
            }
            return FoodLookupResult(hits: [], miss: .unknownBarcode)
        }
        return FoodLookupResult(hits: [], miss: online && live != nil ? .unknownBarcode : .offline)
    }

    public func remember(_ hit: FoodHit) async {
        await store.touchRecent(hit)
    }

    public func saveCustom(_ hit: FoodHit) async {
        var custom = hit
        custom.origin = .custom
        await store.saveCustom(custom)
    }
}

public protocol LiveFoodLookup: Sendable {
    func search(_ query: String) async -> [FoodHit]
    func barcode(_ code: String) async -> FoodHit?
}

struct FoodHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
}

protocol FoodHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> FoodHTTPResponse
}

private struct URLSessionFoodHTTPClient: FoodHTTPClient {
    var session: URLSession

    func data(for request: URLRequest) async throws -> FoodHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return FoodHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

/// OFF + USDA. No child fields. User-Agent names Wastly. Keys stay out of git.
public struct RemoteFoodLookup: LiveFoodLookup {
    private let usdaAPIKey: String?
    private let client: any FoodHTTPClient
    private let userAgent: String

    public init(
        usdaAPIKey: String? = nil,
        urlSession: URLSession = .shared,
        userAgent: String = "Wastly/1.0 (https://github.com/jusso-dev/Wastly)"
    ) {
        self.usdaAPIKey = usdaAPIKey
        self.client = URLSessionFoodHTTPClient(session: urlSession)
        self.userAgent = userAgent
    }

    init(
        usdaAPIKey: String? = nil,
        client: any FoodHTTPClient,
        userAgent: String = "Wastly/1.0 (https://github.com/jusso-dev/Wastly)"
    ) {
        self.usdaAPIKey = usdaAPIKey
        self.client = client
        self.userAgent = userAgent
    }

    public func search(_ query: String) async -> [FoodHit] {
        async let offHits = searchOFF(query)
        async let usdaHits = searchUSDA(query)
        let (off, usda) = await (offHits, usdaHits)
        return FoodHitIdentity.merged(off + usda)
    }

    public func barcode(_ code: String) async -> FoodHit? {
        if let off = await offProduct(code) { return off }
        return await usdaByGTIN(code)
    }

    private func searchOFF(_ query: String) async -> [FoodHit] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_quantity"
            ),
        ]
        guard let url = components?.url, PrivacyAllowlist.isAllowedFoodHost(url.host ?? "") else { return [] }
        guard let response: OFFSearchResponse = await requestJSON(url) else { return [] }
        return response.products.compactMap(Self.hitFromOFF)
    }

    private func offProduct(_ code: String) async -> FoodHit? {
        let path = code.filter(\.isNumber)
        guard !path.isEmpty else { return nil }
        var components = URLComponents(
            string: "https://world.openfoodfacts.org/api/v2/product/\(path).json"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments,serving_quantity"
            ),
        ]
        guard let url = components?.url,
              PrivacyAllowlist.isAllowedFoodHost(url.host ?? ""),
              let response: OFFProductResponse = await requestJSON(url),
              response.status == 1,
              let product = response.product,
              var hit = Self.hitFromOFF(product),
              let remote = product.code ?? response.code,
              Barcode.matches(remote, code)
        else { return nil }
        hit.id = "off:\(remote)"
        hit.barcodeRaw = remote
        return hit
    }

    private func searchUSDA(_ query: String) async -> [FoodHit] {
        let foods = await searchUSDASummaries(
            query,
            dataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"]
        )
        return await resolveUSDAHits(foods)
    }

    private func searchUSDASummaries(
        _ query: String,
        dataTypes: [String]
    ) async -> [USDASearchFood] {
        guard let key = usdaAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return [] }
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "15"),
            URLQueryItem(name: "api_key", value: key),
        ]
        queryItems.append(contentsOf: dataTypes.map {
            URLQueryItem(name: "dataType", value: $0)
        })
        components?.queryItems = queryItems
        guard let url = components?.url, PrivacyAllowlist.isAllowedFoodHost(url.host ?? "") else { return [] }
        guard let response: USDASearchResponse = await requestJSON(url) else { return [] }
        return response.foods
    }

    private func usdaByGTIN(_ code: String) async -> FoodHit? {
        let foods = await searchUSDASummaries(code, dataTypes: ["Branded"])
        guard let food = foods.first(where: {
            guard let raw = $0.gtinUpc else { return false }
            return Barcode.matches(raw, code)
        }) else { return nil }
        return await resolveUSDAHit(food)
    }

    private func resolveUSDAHits(_ foods: [USDASearchFood]) async -> [FoodHit] {
        await withTaskGroup(of: (Int, FoodHit?).self) { group in
            for (index, food) in foods.enumerated() {
                group.addTask { (index, await resolveUSDAHit(food)) }
            }
            var indexed: [(Int, FoodHit)] = []
            for await (index, hit) in group {
                if let hit { indexed.append((index, hit)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func resolveUSDAHit(_ food: USDASearchFood) async -> FoodHit? {
        guard let summary = Self.hitFromUSDA(food) else { return nil }
        guard summary.kilojoulesPer100g <= 0,
              let detail = await usdaDetails(food.fdcId)
        else { return summary }
        return detail
    }

    private func usdaDetails(_ fdcID: Int) async -> FoodHit? {
        guard let key = usdaAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        var components = URLComponents(
            string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcID)"
        )
        components?.queryItems = [URLQueryItem(name: "api_key", value: key)]
        guard let url = components?.url,
              PrivacyAllowlist.isAllowedFoodHost(url.host ?? ""),
              let detail: USDAFoodDetails = await requestJSON(url)
        else { return nil }
        return Self.hitFromUSDA(detail)
    }

    private func requestJSON<Response: Decodable>(_ url: URL) async -> Response? {
        guard PrivacyAllowlist.isAllowedFoodURL(url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let response = try await client.data(for: request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return try JSONDecoder().decode(Response.self, from: response.data)
        } catch {
            return nil
        }
    }

    private static func hitFromOFF(_ product: OFFProduct) -> FoodHit? {
        let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        let kJ = product.nutriments?.energyKilojoulesPer100g?.value
            ?? Energy.storedKilojoules(
                from: product.nutriments?.energyKilocaloriesPer100g?.value ?? 0,
                unit: .kilocalories
            )
        return FoodHit(
            id: "off:\(product.code ?? name)",
            name: name,
            brand: product.brands,
            barcodeRaw: product.code,
            kilojoulesPer100g: kJ,
            servingGrams: product.servingQuantity?.value,
            origin: .openFoodFacts
        )
    }

    private static func hitFromUSDA(_ food: USDASearchFood) -> FoodHit? {
        makeUSDAHit(
            fdcID: food.fdcId,
            description: food.description,
            brand: food.brandOwner,
            gtin: food.gtinUpc,
            servingGrams: food.servingSize?.value,
            kilojoulesPer100g: energyKilojoules(
                food.foodNutrients.map {
                    ($0.nutrientName, $0.nutrientNumber, $0.unitName, $0.value.value)
                }
            )
        )
    }

    private static func hitFromUSDA(_ food: USDAFoodDetails) -> FoodHit? {
        makeUSDAHit(
            fdcID: food.fdcId,
            description: food.description,
            brand: food.brandOwner,
            gtin: food.gtinUpc,
            servingGrams: food.servingSize?.value,
            kilojoulesPer100g: energyKilojoules(
                food.foodNutrients.compactMap { nutrient in
                    guard let definition = nutrient.nutrient,
                          let amount = nutrient.amount?.value
                    else { return nil }
                    return (definition.name, definition.number, definition.unitName, amount)
                }
            )
        )
    }

    private static func makeUSDAHit(
        fdcID: Int,
        description: String,
        brand: String?,
        gtin: String?,
        servingGrams: Double?,
        kilojoulesPer100g: Double
    ) -> FoodHit? {
        let name = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return FoodHit(
            id: "fdc:\(fdcID)",
            name: name,
            brand: brand,
            barcodeRaw: gtin,
            kilojoulesPer100g: kilojoulesPer100g,
            servingGrams: servingGrams,
            origin: .usda
        )
    }

    private static func energyKilojoules(
        _ nutrients: [(name: String, number: String?, unit: String, value: Double)]
    ) -> Double {
        let energyRows = nutrients.filter {
            $0.number == "208" || $0.name.localizedCaseInsensitiveContains("energy")
        }
        if let row = energyRows.first(where: { $0.unit.caseInsensitiveCompare("kJ") == .orderedSame }) {
            return row.value
        }
        if let row = energyRows.first(where: { $0.unit.caseInsensitiveCompare("kcal") == .orderedSame }) {
            return Energy.storedKilojoules(from: row.value, unit: .kilocalories)
        }
        return 0
    }
}

private struct OFFSearchResponse: Decodable, Sendable {
    var products: [OFFProduct]
}

private struct OFFProductResponse: Decodable, Sendable {
    var code: String?
    var status: Int?
    var product: OFFProduct?
}

private struct OFFProduct: Decodable, Sendable {
    var code: String?
    var productName: String?
    var brands: String?
    var nutriments: OFFNutriments?
    var servingQuantity: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case nutriments
        case servingQuantity = "serving_quantity"
    }
}

private struct OFFNutriments: Decodable, Sendable {
    var energyKilojoulesPer100g: FlexibleDouble?
    var energyKilocaloriesPer100g: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case energyKilojoulesPer100g = "energy-kj_100g"
        case energyKilocaloriesPer100g = "energy-kcal_100g"
    }
}

private struct USDASearchResponse: Decodable, Sendable {
    var foods: [USDASearchFood]
}

private struct USDASearchFood: Decodable, Sendable {
    var fdcId: Int
    var description: String
    var dataType: String?
    var brandOwner: String?
    var gtinUpc: String?
    var servingSize: FlexibleDouble?
    var foodNutrients: [USDASearchNutrient]
}

private struct USDASearchNutrient: Decodable, Sendable {
    var nutrientName: String
    var nutrientNumber: String?
    var unitName: String
    var value: FlexibleDouble
}

private struct USDAFoodDetails: Decodable, Sendable {
    var fdcId: Int
    var description: String
    var brandOwner: String?
    var gtinUpc: String?
    var servingSize: FlexibleDouble?
    var foodNutrients: [USDADetailNutrient]
}

private struct USDADetailNutrient: Decodable, Sendable {
    var amount: FlexibleDouble?
    var nutrient: USDANutrientDefinition?
}

private struct USDANutrientDefinition: Decodable, Sendable {
    var name: String
    var number: String?
    var unitName: String
}

private struct FlexibleDouble: Decodable, Sendable {
    var value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self),
                  let number = Double(string) {
            value = number
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a number or numeric string."
                )
            )
        }
    }
}
