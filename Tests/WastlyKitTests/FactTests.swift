import Foundation
import Testing
@testable import WastlyKit

struct FactTests {
    @Test func totalsUseLocalMathsAndInclusiveCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = Date(timeIntervalSince1970: 3_600)
        let secondDay = Date(timeIntervalSince1970: 90_000)
        let now = Date(timeIntervalSince1970: 176_400)
        let logs = [
            FoodLog(
                loggedAt: firstDay,
                meal: .breakfast,
                foodName: "Banana",
                eatenGrams: 100,
                wastedGrams: 20,
                kilojoulesPer100g: 400
            ),
            FoodLog(
                loggedAt: secondDay,
                meal: .lunch,
                foodName: "Toast",
                eatenGrams: 50,
                wastedGrams: 30,
                kilojoulesPer100g: 1_000
            ),
        ]

        let totals = FactTotals.from(logs: logs, now: now, calendar: calendar)

        #expect(totals.days == 3)
        #expect(totals.eatenGrams == 150)
        #expect(totals.wastedGrams == 50)
        #expect(totals.eatenKilojoules == 900)
        #expect(totals.wastedKilojoules == 380)
        #expect(totals.wasteRatio == 0.25)
        #expect(totals.topFood == "Banana")
    }

    @Test func hashStableForSameInputs() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        #expect(a.inputsHash == b.inputsHash)
    }

    @Test func hashIgnoresSmallMovements() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 120, wastedGrams: 20, eatenKilojoules: 450, wastedKilojoules: 80, topFood: "Banana")
        #expect(a.inputsHash == b.inputsHash)
    }

    @Test func hashChangesWhenTotalsMoveMaterially() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 500, wastedGrams: 300, eatenKilojoules: 2_000, wastedKilojoules: 1_200, topFood: "Banana")
        #expect(a.inputsHash != b.inputsHash)
    }

    @Test func hashIncludesEnergy() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 1_200, wastedKilojoules: 800, topFood: "Banana")
        #expect(a.inputsHash != b.inputsHash)
    }

    @Test func equivalentFoodNamesHashAndRenderConsistently() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "  Banana  ")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "banana")
        #expect(a.inputsHash == b.inputsHash)
        #expect(FactTemplates.fact(for: a) == FactTemplates.fact(for: b))
        #expect(FactTemplates.fact(for: a).contains("banana"))
    }

    @Test func energyOnlyMovementChangesRenderedFact() {
        let a = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let b = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 1_200, wastedKilojoules: 800, topFood: "Banana")
        let first = FactTemplates.fact(for: a)
        let second = FactTemplates.fact(for: b)
        #expect(first != second)
        #expect(first.contains("400 kJ"))
        #expect(first.contains("40 kJ"))
    }

    @Test func scalePickerKeepsComparisonsProportional() {
        #expect(FactScale.pick(forWastedGrams: 39) == .bites)
        #expect(FactScale.pick(forWastedGrams: 40) == .lunchbox)
        #expect(FactScale.pick(forWastedGrams: 499) == .lunchbox)
        #expect(FactScale.pick(forWastedGrams: 500) == .footy)
        #expect(FactScale.pick(forWastedGrams: 19_999) == .footy)
        #expect(FactScale.pick(forWastedGrams: 20_000) == .wheelieBin)
        #expect(FactScale.pick(forWastedGrams: 49_999_999) == .wheelieBin)
        #expect(FactScale.pick(forWastedGrams: 50_000_000) == .mcg)
    }

    @Test func cacheRegeneratesDailyOrAfterMaterialMovement() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 100_000)
        let baseline = FactTotals(days: 2, eatenGrams: 100, wastedGrams: 10, eatenKilojoules: 400, wastedKilojoules: 40, topFood: "Banana")
        let smallMove = FactTotals(days: 2, eatenGrams: 120, wastedGrams: 20, eatenKilojoules: 450, wastedKilojoules: 80, topFood: "Banana")
        let largeMove = FactTotals(days: 2, eatenGrams: 500, wastedGrams: 300, eatenKilojoules: 2_000, wastedKilojoules: 1_200, topFood: "Banana")

        #expect(FactCachePolicy.shouldRegenerate(
            cachedInputsHash: nil,
            cachedAt: nil,
            totals: baseline,
            now: now,
            calendar: calendar
        ))
        #expect(FactCachePolicy.shouldRegenerate(
            cachedInputsHash: baseline.inputsHash,
            cachedAt: now.addingTimeInterval(-3_600),
            totals: smallMove,
            now: now,
            calendar: calendar
        ) == false)
        #expect(FactCachePolicy.shouldRegenerate(
            cachedInputsHash: baseline.inputsHash,
            cachedAt: now.addingTimeInterval(-3_600),
            totals: largeMove,
            now: now,
            calendar: calendar
        ))
        #expect(FactCachePolicy.shouldRegenerate(
            cachedInputsHash: baseline.inputsHash,
            cachedAt: now,
            totals: baseline,
            now: now.addingTimeInterval(86_400),
            calendar: calendar
        ))
    }

    @Test func smallWasteUsesSmallObject() {
        let totals = FactTotals(days: 3, eatenGrams: 400, wastedGrams: 20, eatenKilojoules: 1600, wastedKilojoules: 80, topFood: "Toast")
        let text = FactTemplates.fact(for: totals, firstName: "Alex")
        #expect(text.contains("lunchbox"))
        #expect(text.contains("MCG") == false)
    }

    @Test func mcgAppearsOnlyAtAnHonestScale() {
        let wheelieBin = FactTotals(days: 3, eatenGrams: 50_000_000, wastedGrams: 49_999_999, eatenKilojoules: 1, wastedKilojoules: 1)
        let mcg = FactTotals(days: 3, eatenGrams: 50_000_000, wastedGrams: 50_000_000, eatenKilojoules: 1, wastedKilojoules: 1)
        #expect(FactTemplates.fact(for: wheelieBin).contains("MCG") == false)
        #expect(FactTemplates.fact(for: mcg).contains("MCG"))
    }

    @Test func offlineTemplateAppearsAfterLogs() {
        let totals = FactTotals(days: 2, eatenGrams: 300, wastedGrams: 50, eatenKilojoules: 1_200, wastedKilojoules: 200, topFood: "Banana")
        let text = FactTemplates.fact(for: totals, firstName: "Alex")
        #expect(text.contains("No logs") == false)
        #expect(text.contains("Alex"))
        #expect(text.isEmpty == false)
    }

    @Test func emptyLogsStayQuiet() {
        let text = FactTemplates.fact(for: FactTotals(days: 0, eatenGrams: 0, wastedGrams: 0, eatenKilojoules: 0, wastedKilojoules: 0))
        #expect(text.contains("No logs"))
    }
}
