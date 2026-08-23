import Foundation
import Testing
@testable import WastlyKit

struct BarcodeExactMatchTests {
    @Test func paddedOFFRequestAcceptsTheSameUnpaddedProductCode() async throws {
        let lookup = RemoteFoodLookup(client: BarcodeFixtureClient(mode: .offExact))

        let hit = try #require(await lookup.barcode("03017620422003"))

        #expect(hit.name == "Nutella")
        #expect(hit.barcodeRaw == "3017620422003")
    }

    @Test func offRejectsAMismatchedReturnedCode() async {
        let lookup = RemoteFoodLookup(client: BarcodeFixtureClient(mode: .offMismatch))

        #expect(await lookup.barcode("4011") == nil)
    }

    @Test func offRejectsAProductWithoutAnyReturnedCode() async {
        let lookup = RemoteFoodLookup(client: BarcodeFixtureClient(mode: .offMissingCode))

        #expect(await lookup.barcode("4011") == nil)
    }

    @Test func usdaSkipsFuzzyFirstHitAndAcceptsLaterExactPaddedGTIN() async throws {
        let lookup = RemoteFoodLookup(
            usdaAPIKey: "fixture-key",
            client: BarcodeFixtureClient(mode: .usdaExactAfterFuzzy)
        )

        let hit = try #require(await lookup.barcode("4011"))

        #expect(hit.id == "fdc:900002")
        #expect(hit.name == "Exact padded product")
        #expect(hit.barcodeRaw == "0004011")
        #expect(abs(hit.kilojoulesPer100g - 209.2) < 0.001)
    }

    @Test func unknownBarcodeNeverUsesAFuzzyProductsEnergy() async {
        let lookup = RemoteFoodLookup(
            usdaAPIKey: "fixture-key",
            client: BarcodeFixtureClient(mode: .usdaFuzzyOnly)
        )

        #expect(await lookup.barcode("4011") == nil)
    }
}

private actor BarcodeFixtureClient: FoodHTTPClient {
    enum Mode: Sendable {
        case offExact
        case offMismatch
        case offMissingCode
        case usdaExactAfterFuzzy
        case usdaFuzzyOnly
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func data(for request: URLRequest) async throws -> FoodHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let fixtureName: String
        if url.host == "world.openfoodfacts.org" {
            fixtureName = switch mode {
            case .offExact:
                "off-product-nutella"
            case .offMismatch:
                "off-product-mismatch"
            case .offMissingCode:
                "off-product-missing-code"
            case .usdaExactAfterFuzzy, .usdaFuzzyOnly:
                "off-product-not-found"
            }
        } else if url.host == "api.nal.usda.gov", url.path == "/fdc/v1/foods/search" {
            fixtureName = switch mode {
            case .usdaExactAfterFuzzy:
                "usda-barcode-padded"
            case .usdaFuzzyOnly:
                "usda-barcode-fuzzy-only"
            case .offExact, .offMismatch, .offMissingCode:
                throw URLError(.resourceUnavailable)
            }
        } else {
            throw URLError(.resourceUnavailable)
        }
        guard let fixtureURL = Bundle.module.url(
            forResource: fixtureName,
            withExtension: "json"
        ) else { throw URLError(.fileDoesNotExist) }
        return FoodHTTPResponse(
            data: try Data(contentsOf: fixtureURL),
            statusCode: 200
        )
    }
}
