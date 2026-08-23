import Testing
@testable import WastlyKit

struct EnergyTests {
    @Test func kilocalorieRoundTrip() {
        let kJ = Energy.kilojoules(fromKilocalories: 1000)
        #expect(abs(kJ - 4184) < 0.001)
        #expect(abs(Energy.kilocalories(fromKilojoules: 4184) - 1000) < 0.001)
    }

    @Test func per100gScaling() {
        #expect(Energy.energyKilojoules(grams: 30, kilojoulesPer100g: 1470) == 441)
    }

    @Test func displayUsesUnit() {
        #expect(Energy.display(4184, unit: .kilocalories) == "1,000 kcal" || Energy.display(4184, unit: .kilocalories).contains("1000"))
        #expect(Energy.display(4184, unit: .kilojoules).contains("kJ"))
    }
}
