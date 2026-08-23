import Foundation
import Testing
@testable import WastlyKit

struct RemoteFactGeneratorTests {
    private let endpoint = URL(string: "https://facts.example/v1/generate")!
    private let totals = FactTotals(
        days: 3,
        eatenGrams: 800,
        wastedGrams: 500,
        eatenKilojoules: 3_200,
        wastedKilojoules: 2_000,
        topFood: "Toast"
    )

    @Test func requestContainsOnlyAllowedAggregatesAndConfigurationHeaders() throws {
        let request = try FactRequestBuilder.make(
            url: endpoint,
            configuredHost: "facts.example",
            apiKey: "test-key",
            totals: totals,
            firstName: "Sam"
        )
        let body = try #require(request.httpBody)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        #expect(Set(object.keys) == ["first_name", "days", "eaten_g", "wasted_g", "top_food"])
        #expect(object["weightKg"] == nil)
        #expect(object["photo"] == nil)
        #expect(object["dateOfBirth"] == nil)
        #expect(request.timeoutInterval == 12)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "X-Wastly-Fact-Prompt") == FactPrompt.version)
        #expect(String(data: body, encoding: .utf8)?.contains("test-key") == false)
        try PrivacyGuard.assertFactJSON(body)
    }

    @Test func promptRequiresNeutralCopyAndDebugWorking() {
        let prompt = FactPrompt.systemInstructions.lowercased()
        #expect(prompt.contains("one to three"))
        #expect(prompt.contains("grams-to-object"))
        #expect(prompt.contains("debug"))
        #expect(prompt.contains("obesity"))
        #expect(prompt.contains("too much"))
        #expect(prompt.contains("be better"))
    }

    @Test func validResponseReturnsOneToThreeFactsAndWorking() async throws {
        let client = StubFactHTTPClient(.response(FactHTTPResponse(
            data: Data(#"{"facts":["About one footy by weight.","That is lunchbox scale."],"debug":"500 g / 500 g per footy = 1 footy"}"#.utf8),
            statusCode: 200
        )))
        let generator = RemoteFactGenerator(endpoint: endpoint, client: client)

        let result = try await generator.generate(totals: totals, firstName: "Sam")

        #expect(result.facts.count == 2)
        #expect(result.text.contains("\n\n"))
        #expect(result.debug == "500 g / 500 g per footy = 1 footy")
    }

    @Test func shamingCopyIsRejected() async {
        let client = StubFactHTTPClient(.response(FactHTTPResponse(
            data: Data(#"{"facts":["That was too much food."],"debug":"500 g / 500 g = 1"}"#.utf8),
            statusCode: 200
        )))
        let generator = RemoteFactGenerator(endpoint: endpoint, client: client)

        await #expect(throws: FactGenerationError.self) {
            try await generator.generate(totals: totals, firstName: nil)
        }
    }

    @Test func fourHundredResponseLeavesTemplateInPlace() async {
        let client = StubFactHTTPClient(.response(FactHTTPResponse(
            data: Data(#"{"error":"rate limited"}"#.utf8),
            statusCode: 429
        )))
        let generator = RemoteFactGenerator(endpoint: endpoint, client: client)

        let result = await FactService.generateOrFallback(
            totals: totals,
            firstName: "Sam",
            using: generator
        )

        #expect(result.source == .template)
        #expect(result.text == FactTemplates.fact(for: totals, firstName: "Sam"))
    }

    @Test func timeoutLeavesTemplateInPlace() async {
        let generator = RemoteFactGenerator(
            endpoint: endpoint,
            client: StubFactHTTPClient(.failure)
        )

        let result = await FactService.generateOrFallback(
            totals: totals,
            firstName: "Sam",
            using: generator
        )

        #expect(result.source == .template)
        #expect(result.text == FactTemplates.fact(for: totals, firstName: "Sam"))
    }
}

private struct StubFactHTTPClient: FactHTTPClient {
    enum Outcome: Sendable {
        case response(FactHTTPResponse)
        case failure
    }

    var outcome: Outcome

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func data(for request: URLRequest) async throws -> FactHTTPResponse {
        switch outcome {
        case let .response(response):
            return response
        case .failure:
            throw URLError(.timedOut)
        }
    }
}
