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
        var hits = await store.searchLocal(trimmed)
        if !hits.isEmpty {
            return FoodLookupResult(hits: hits)
        }
        if online, let live {
            hits = await live.search(trimmed)
            for hit in hits { await store.upsertCache(hit) }
            return FoodLookupResult(hits: hits, miss: hits.isEmpty ? .unknownBarcode : nil)
        }
        return FoodLookupResult(hits: [], miss: online ? .unknownBarcode : .offline)
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
                await store.upsertCache(hit)
                return FoodLookupResult(hits: [hit])
            }
            return FoodLookupResult(hits: [], miss: .unknownBarcode)
        }
        return FoodLookupResult(hits: [], miss: online ? .unknownBarcode : .offline)
    }

    public func remember(_ hit: FoodHit) async {
        await store.touchRecent(hit)
    }

    public func saveCustom(_ hit: FoodHit) async {
        var custom = hit
        custom.origin = .custom
        await store.upsertCache(custom, isCustom: true)
    }
}

public protocol LiveFoodLookup: Sendable {
    func search(_ query: String) async -> [FoodHit]
    func barcode(_ code: String) async -> FoodHit?
}

/// OFF + USDA. No child fields. User-Agent names Wastly. Keys stay out of git.
public struct RemoteFoodLookup: LiveFoodLookup {
    public var usdaAPIKey: String?
    public var urlSession: URLSession
    public var userAgent: String

    public init(usdaAPIKey: String? = nil, urlSession: URLSession = .shared, userAgent: String = "Wastly/1.0 (https://github.com/jusso-dev/Wastly)") {
        self.usdaAPIKey = usdaAPIKey
        self.urlSession = urlSession
        self.userAgent = userAgent
    }

    public func search(_ query: String) async -> [FoodHit] {
        var hits: [FoodHit] = []
        hits.append(contentsOf: await searchOFF(query))
        hits.append(contentsOf: await searchUSDA(query))
        return dedupe(hits)
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
        ]
        guard let url = components?.url, PrivacyAllowlist.isAllowedFoodHost(url.host ?? "") else { return [] }
        guard let json = await getJSON(url) else { return [] }
        let products = json["products"] as? [[String: Any]] ?? []
        return products.compactMap(Self.hitFromOFF)
    }

    private func offProduct(_ code: String) async -> FoodHit? {
        let path = Barcode.normalized(code)
        guard !path.isEmpty else { return nil }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(path).json") else { return nil }
        guard PrivacyAllowlist.isAllowedFoodHost(url.host ?? "") else { return nil }
        guard let json = await getJSON(url) else { return nil }
        guard let product = json["product"] as? [String: Any] else { return nil }
        guard let hit = Self.hitFromOFF(product) else { return nil }
        let remote = (product["code"] as? String) ?? path
        guard Barcode.matches(remote, code) else { return nil }
        return hit
    }

    private func searchUSDA(_ query: String) async -> [FoodHit] {
        guard let key = usdaAPIKey, !key.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "15"),
            URLQueryItem(name: "api_key", value: key),
        ]
        guard let url = components?.url, PrivacyAllowlist.isAllowedFoodHost(url.host ?? "") else { return [] }
        guard let json = await getJSON(url) else { return [] }
        let foods = json["foods"] as? [[String: Any]] ?? []
        return foods.compactMap(Self.hitFromUSDA)
    }

    private func usdaByGTIN(_ code: String) async -> FoodHit? {
        let hits = await searchUSDA(code)
        return hits.first(where: { hit in
            guard let raw = hit.barcodeRaw else { return false }
            return Barcode.matches(raw, code)
        })
    }

    private func getJSON(_ url: URL) async -> [String: Any]? {
        guard PrivacyAllowlist.isAllowedFoodURL(url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func dedupe(_ hits: [FoodHit]) -> [FoodHit] {
        var seen = Set<String>()
        return hits.filter { hit in
            let key = hit.barcodeNormalized ?? hit.id
            return seen.insert(key).inserted
        }
    }

    static func hitFromOFF(_ product: [String: Any]) -> FoodHit? {
        let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        let code = product["code"] as? String
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let kJ = number(nutriments["energy-kj_100g"]) ?? Energy.kilojoules(fromKilocalories: number(nutriments["energy-kcal_100g"]) ?? 0)
        return FoodHit(
            id: "off:\(code ?? name)",
            name: name,
            brand: product["brands"] as? String,
            barcodeRaw: code,
            kilojoulesPer100g: kJ,
            servingGrams: number(product["serving_quantity"]),
            origin: .openFoodFacts
        )
    }

    static func hitFromUSDA(_ food: [String: Any]) -> FoodHit? {
        let name = (food["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        let fdc = food["fdcId"].map { "\($0)" } ?? name
        let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
        let kcal = nutrients.compactMap { row -> Double? in
            let n = (row["nutrientName"] as? String) ?? ""
            if n.localizedCaseInsensitiveContains("Energy") {
                return number(row["value"])
            }
            return nil
        }.first ?? 0
        let gtin = food["gtinUpc"] as? String
        return FoodHit(
            id: "fdc:\(fdc)",
            name: name,
            brand: food["brandOwner"] as? String,
            barcodeRaw: gtin,
            kilojoulesPer100g: Energy.kilojoules(fromKilocalories: kcal),
            servingGrams: nil,
            origin: .usda
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
