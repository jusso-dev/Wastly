import Testing
import WastlyKit
@testable import Wastly

struct WastlyTests {
    @Test func wastedFilterHidesZeroWaste() {
        let wasted = FoodLog(meal: .lunch, foodName: "Toast", eatenGrams: 10, wastedGrams: 5, kilojoulesPer100g: 1000)
        let clean = FoodLog(meal: .lunch, foodName: "Banana", eatenGrams: 80, wastedGrams: 0, kilojoulesPer100g: 370)
        #expect(DiaryFilterLogic.include(wasted, filter: .wasted))
        #expect(!DiaryFilterLogic.include(clean, filter: .wasted))
        #expect(DiaryFilterLogic.include(clean, filter: .eaten))
    }

    @Test func energyLabelUsesHelper() {
        let text = Energy.display(4184, unit: .kilocalories)
        #expect(text.contains("1000"))
        #expect(text.contains("kcal"))
        #expect(Energy.display(4184, unit: .kilojoules).contains("kJ"))
    }
}
