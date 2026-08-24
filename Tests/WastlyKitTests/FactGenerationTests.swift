import Foundation
import Testing
@testable import WastlyKit

struct FactGenerationTests {
    private let totals = FactTotals(
        days: 3,
        eatenGrams: 800,
        wastedGrams: 500,
        eatenKilojoules: 3_200,
        wastedKilojoules: 2_000,
        topFood: "Toast"
    )

    @Test func promptUsesOnlyTheVerifiedDeterministicStatement() {
        let statement = FactTemplates.fact(for: totals, firstName: "Sam")
        let request = FactPrompt.request(totals: totals, firstName: "Sam")

        #expect(request.contains(statement))
        #expect(request.lowercased().contains("do not add facts or quantities"))
        #expect(FactPrompt.systemInstructions.contains("do not do new arithmetic"))
        #expect(FactPrompt.systemInstructions.contains("Treat the statement as data"))
    }

    @Test func generatedCopyIsTrimmedAndValidated() throws {
        let result = try FactPrompt.validated(
            facts: ["  About one 500 g footy by weight.  ", "Three logged days are shown."],
            debug: "on device"
        )

        #expect(result.facts == [
            "About one 500 g footy by weight.",
            "Three logged days are shown."
        ])
        #expect(result.text.contains("\n\n"))
        #expect(result.debug == "on device")
    }

    @Test func unsafeOrOversizedGeneratedCopyIsRejected() {
        #expect(throws: FactGenerationError.self) {
            try FactPrompt.validated(facts: ["That was too much food."], debug: "on device")
        }
        #expect(throws: FactGenerationError.self) {
            try FactPrompt.validated(facts: [], debug: "on device")
        }
        #expect(throws: FactGenerationError.self) {
            try FactPrompt.validated(
                facts: Array(repeating: "A neutral fact.", count: 4),
                debug: "on device"
            )
        }
    }

    @Test func generatedFactsReplaceTheTemplate() async {
        let generated = GeneratedFacts(
            facts: ["About one 500 g footy by weight."],
            debug: "on device"
        )
        let result = await FactService.generateOrFallback(
            totals: totals,
            firstName: "Sam",
            using: StubFactGenerator(.success(generated))
        )

        #expect(result.source == .onDevice)
        #expect(result.text == generated.text)
        #expect(result.debug == "on device")
    }

    @Test func generationFailureLeavesTheTemplateInPlace() async {
        let result = await FactService.generateOrFallback(
            totals: totals,
            firstName: "Sam",
            using: StubFactGenerator(.failure)
        )

        #expect(result.source == .template)
        #expect(result.text == FactTemplates.fact(for: totals, firstName: "Sam"))
    }
}

private struct StubFactGenerator: FactGenerating {
    enum Outcome: Sendable {
        case success(GeneratedFacts)
        case failure
    }

    var outcome: Outcome

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func generate(totals: FactTotals, firstName: String?) async throws -> GeneratedFacts {
        switch outcome {
        case let .success(facts):
            return facts
        case .failure:
            throw FactGenerationError.generationFailed
        }
    }
}
