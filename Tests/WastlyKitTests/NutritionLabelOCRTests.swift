import Foundation
import Testing
@testable import WastlyKit

struct NutritionLabelOCRTests {
    @Test func bundledLabelRunsOnDeviceAndYieldsEditableEnergy() async throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "nutrition-label-energy",
                withExtension: "jpg"
            )
        )
        let imageData = try Data(contentsOf: fixtureURL)

        let scan = try await NutritionLabelOCR().recognize(imageData: imageData)

        #expect(scan.lines.map(\.text).joined(separator: " ").contains("1470"))
        #expect(abs((scan.energyKilojoulesPer100g ?? 0) - 1_470) < 1)
        #expect(abs((scan.energyKilojoulesPerServing ?? 0) - 441) < 1)
        #expect(scan.servingGrams == 30)
        #expect(scan.confidence > 0.8)
    }

    @Test func parserConvertsKcalAndCanDerivePer100g() {
        let scan = NutritionLabelParser.parse(lines: [
            RecognizedLabelLine(text: "Serving size: 50 g", confidence: 0.9),
            RecognizedLabelLine(text: "Energy per serving 100 kcal", confidence: 0.8),
        ])

        #expect(abs((scan.energyKilojoulesPerServing ?? 0) - 418.4) < 0.001)
        #expect(abs((scan.energyKilojoulesPer100g ?? 0) - 836.8) < 0.001)
        #expect(scan.servingGrams == 50)
        #expect(abs(scan.confidence - 0.85) < 0.001)
    }
}
