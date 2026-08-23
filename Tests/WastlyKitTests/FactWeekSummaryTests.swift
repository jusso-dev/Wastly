import Foundation
import Testing
@testable import WastlyKit

struct FactWeekSummaryTests {
    @Test func emptyWeekHasNoBars() {
        let summary = FactWeekSummary.from(
            logs: [],
            now: Date(timeIntervalSince1970: 900_000),
            calendar: utcCalendar
        )

        #expect(summary.days.count == 7)
        #expect(summary.hasLogs == false)
        #expect(summary.maximumGrams == 0)
        #expect(summary.days.allSatisfy {
            summary.barHeight(for: $0.eatenGrams) == 0
                && summary.barHeight(for: $0.wastedGrams) == 0
        })
    }

    @Test func zeroAmountsStayInvisibleBesideRealBars() {
        let now = Date(timeIntervalSince1970: 900_000)
        let logs = [
            FoodLog(
                loggedAt: now.addingTimeInterval(-3_600),
                meal: .dinner,
                foodName: "Pasta",
                eatenGrams: 100,
                wastedGrams: 0,
                kilojoulesPer100g: 600
            ),
            FoodLog(
                loggedAt: now.addingTimeInterval(-6 * 86_400),
                meal: .breakfast,
                foodName: "Toast",
                eatenGrams: 0,
                wastedGrams: 20,
                kilojoulesPer100g: 1_000
            ),
            FoodLog(
                loggedAt: now.addingTimeInterval(-8 * 86_400),
                meal: .lunch,
                foodName: "Old log",
                eatenGrams: 999,
                wastedGrams: 999,
                kilojoulesPer100g: 1
            ),
        ]

        let summary = FactWeekSummary.from(logs: logs, now: now, calendar: utcCalendar)

        #expect(summary.hasLogs)
        #expect(summary.maximumGrams == 100)
        #expect(summary.days.first?.wastedGrams == 20)
        #expect(summary.days.last?.eatenGrams == 100)
        #expect(summary.barHeight(for: 100) == 80)
        #expect(summary.barHeight(for: 20) == 16)
        #expect(summary.barHeight(for: 0) == 0)
    }

    @Test func selectedChildWeekExcludesOtherChildren() {
        let first = Child(firstName: "Alex", dateOfBirth: .now)
        let second = Child(firstName: "Sam", dateOfBirth: .now)
        let now = Date(timeIntervalSince1970: 900_000)
        let logs = [
            FoodLog(
                loggedAt: now,
                meal: .lunch,
                foodName: "Apple",
                eatenGrams: 40,
                wastedGrams: 5,
                kilojoulesPer100g: 200,
                child: first
            ),
            FoodLog(
                loggedAt: now,
                meal: .lunch,
                foodName: "Banana",
                eatenGrams: 900,
                wastedGrams: 800,
                kilojoulesPer100g: 300,
                child: second
            ),
        ]
        let selectedLogs = ChildSelection.logs(for: first.id, from: logs)

        let summary = FactWeekSummary.from(
            logs: selectedLogs,
            now: now,
            calendar: utcCalendar
        )

        #expect(summary.days.last?.eatenGrams == 40)
        #expect(summary.days.last?.wastedGrams == 5)
        #expect(summary.maximumGrams == 45)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
