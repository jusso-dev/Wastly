import Testing
@testable import WastlyKit

struct EnergyTests {
    @Test func sharedHelperKeepsKJAsTheStorageBoundary() {
        let stored = Energy.storedKilojoules(from: 1_000, unit: .kilocalories)

        #expect(abs(stored - 4_184) < 0.001)
        let displayed = Energy.value(fromStoredKilojoules: stored, unit: .kilocalories)
        #expect(abs(displayed - 1_000) < 0.001)
        #expect(Energy.value(fromStoredKilojoules: stored, unit: .kilojoules) == 4_184)
    }

    @Test func kilocalorieRoundTrip() {
        let kilojoules = Energy.kilojoules(fromKilocalories: 1000)
        #expect(abs(kilojoules - 4184) < 0.001)
        #expect(abs(Energy.kilocalories(fromKilojoules: 4184) - 1000) < 0.001)
    }

    @Test func per100gScaling() {
        #expect(Energy.energyKilojoules(grams: 30, kilojoulesPer100g: 1470) == 441)
    }

    @Test func displayUsesUnit() {
        let calories = Energy.display(4184, unit: .kilocalories)
        #expect(calories == "1,000 kcal" || calories.contains("1000"))
        #expect(Energy.display(4184, unit: .kilojoules).hasSuffix("kJ"))
    }
}
