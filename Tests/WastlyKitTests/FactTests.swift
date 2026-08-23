import Testing
@testable import WastlyKit

struct FactTests {
    @Test func hashStableForSameInputs() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        #expect(a.inputsHash == b.inputsHash)
    }

    @Test func hashChangesWhenTotalsMove() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 80, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        #expect(a.inputsHash != b.inputsHash)
    }

    @Test func smallWasteUsesSmallObject() {
        let totals = FactTotals(days: 3, eatenGrams: 400, wastedGrams: 20, eatenKilojoules: 1600, wastedKilojoules: 80, topFood: "Toast")
        let text = FactTemplates.fact(for: totals, firstName: "Alex")
        #expect(text.contains("lunchbox") || text.contains("crumb"))
        #expect(text.contains("stadium") == false)
    }

    @Test func emptyLogsStayQuiet() {
        let text = FactTemplates.fact(for: FactTotals(days: 0, eatenGrams: 0, wastedGrams: 0, eatenKilojoules: 0, wastedKilojoules: 0))
        #expect(text.contains("No logs"))
    }
}
