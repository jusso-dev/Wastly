import Foundation
import Testing
@testable import WastlyKit

struct FoodDirectoryTests {
    @Test func appleSearchUsesFDCGenericSearchAndDetailsFixtures() async throws {
        let client = FixtureFoodHTTPClient()
        let lookup = RemoteFoodLookup(
            usdaAPIKey: "fixture-key",
            client: client,
            userAgent: "Wastly/fixture-tests (https://github.com/jusso-dev/Wastly)"
        )

        let hits = await lookup.search("apple")

        let apple = try #require(hits.first(where: { $0.id == "fdc:171688" }))
        #expect(apple.name == "Apples, raw, with skin")
        #expect(apple.origin == .usda)
        #expect(abs(apple.kilojoulesPer100g - 217.568) < 0.001)

        let requests = await client.recordedRequests()
        #expect(requests.count == 3)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Wastly/") == true
        })
        let searchRequest = try #require(requests.first {
            $0.url?.path == "/fdc/v1/foods/search"
        })
        let components = try #require(searchRequest.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        let dataTypes = components.queryItems?
            .filter { $0.name == "dataType" }
            .compactMap(\.value)
        #expect(Set(dataTypes ?? []) == ["Foundation", "SR Legacy", "Survey (FNDDS)"])
        #expect(components.queryItems?.first(where: { $0.name == "api_key" })?.value == "fixture-key")
        #expect(requests.contains { $0.url?.path == "/fdc/v1/food/171688" })
    }

    @Test func knownOFFBarcodeReturnsRecordedProduct() async throws {
        let client = FixtureFoodHTTPClient()
        let lookup = RemoteFoodLookup(client: client)

        let hit = try #require(await lookup.barcode("3017620422003"))

        #expect(hit.name == "Nutella")
        #expect(hit.brand == "Ferrero")
        #expect(hit.barcodeRaw == "3017620422003")
        #expect(hit.origin == .openFoodFacts)
        #expect(hit.servingGrams == 15)
        #expect(abs(hit.kilojoulesPer100g - 2_255.176) < 0.001)

        let request = try #require(await client.recordedRequests().first)
        #expect(request.url?.path == "/api/v2/product/3017620422003.json")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Wastly/") == true)
        let fields = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }?.queryItems?.first(where: { $0.name == "fields" })?.value
        #expect(fields?.contains("nutriments") == true)
    }

    @Test func customAndRecentHitsLeadMergedResultsAndRemoteHitsAreCached() async throws {
        let store = try LocalFoodStore.inMemory()
        let customApple = FoodHit(
            id: "custom:apple",
            name: "Apple",
            kilojoulesPer100g: 220,
            origin: .custom
        )
        let live = StubLiveFoodLookup(hits: [
            FoodHit(
                id: "fdc:duplicate-apple",
                name: "apple",
                kilojoulesPer100g: 218,
                origin: .usda
            ),
            FoodHit(
                id: "fdc:pear",
                name: "Apple pear",
                kilojoulesPer100g: 180,
                origin: .usda
            ),
        ])
        let directory = LocalFirstFoodDirectory(store: store, live: live)
        await directory.saveCustom(customApple)

        let result = await directory.search("apple", online: true)

        #expect(result.hits.map(\.id) == ["custom:apple", "fdc:pear"])
        #expect(result.miss == nil)
        let cachedApples = await store.searchLocal("Apple")
        #expect(cachedApples.filter { $0.name.caseInsensitiveCompare("Apple") == .orderedSame }.count == 1)
        #expect(cachedApples.first?.origin == .custom)
        #expect(cachedApples.first?.kilojoulesPer100g == 220)
        #expect(cachedApples.contains(where: { $0.id == "fdc:pear" }))
    }

    @Test func networkFailuresReturnEmptyResultsInsteadOfThrowing() async {
        let lookup = RemoteFoodLookup(
            usdaAPIKey: "fixture-key",
            client: FailingFoodHTTPClient()
        )

        #expect(await lookup.search("apple").isEmpty)
        #expect(await lookup.barcode("3017620422003") == nil)
    }
}

private actor FixtureFoodHTTPClient: FoodHTTPClient {
    private var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> FoodHTTPResponse {
        requests.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        let fixtureName: String
        switch (url.host, url.path) {
        case ("world.openfoodfacts.org", "/cgi/search.pl"):
            fixtureName = "off-search-empty"
        case ("world.openfoodfacts.org", "/api/v2/product/3017620422003.json"):
            fixtureName = "off-product-nutella"
        case ("api.nal.usda.gov", "/fdc/v1/foods/search"):
            fixtureName = "usda-search-apple"
        case ("api.nal.usda.gov", "/fdc/v1/food/171688"):
            fixtureName = "usda-detail-apple"
        default:
            throw URLError(.resourceUnavailable)
        }
        let fixtureURL = try #require(
            Bundle.module.url(forResource: fixtureName, withExtension: "json")
        )
        return FoodHTTPResponse(
            data: try Data(contentsOf: fixtureURL),
            statusCode: 200
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private struct StubLiveFoodLookup: LiveFoodLookup {
    var hits: [FoodHit]

    func search(_ query: String) async -> [FoodHit] {
        hits
    }

    func barcode(_ code: String) async -> FoodHit? {
        nil
    }
}

private struct FailingFoodHTTPClient: FoodHTTPClient {
    func data(for request: URLRequest) async throws -> FoodHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}
