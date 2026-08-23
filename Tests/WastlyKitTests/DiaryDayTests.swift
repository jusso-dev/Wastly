import Foundation
import Testing
@testable import WastlyKit

struct DiaryDayTests {
    @Test func weetBixRowAndDayTotalsMatch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let selectedDay = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 23,
            hour: 12
        )))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: selectedDay))
        let weetBix = FoodLog(
            loggedAt: selectedDay,
            meal: .breakfast,
            foodName: "Weet-Bix",
            eatenGrams: 30,
            wastedGrams: 10,
            kilojoulesPer100g: 1_470
        )
        let tomorrow = FoodLog(
            loggedAt: nextDay,
            meal: .breakfast,
            foodName: "Tomorrow",
            eatenGrams: 100,
            wastedGrams: 100,
            kilojoulesPer100g: 1_000
        )

        let rows = DiaryDay.logs([weetBix, tomorrow], on: selectedDay, calendar: calendar)
        let totals = DiaryDay.totals(for: rows)

        #expect(rows.map(\.foodName) == ["Weet-Bix"])
        #expect(rows.first?.eatenGrams == 30)
        #expect(rows.first?.wastedGrams == 10)
        #expect(totals.eatenGrams == 30)
        #expect(totals.wastedGrams == 10)
        #expect(abs(totals.eatenKilojoules - 441) < 0.001)
        #expect(abs(totals.wastedKilojoules - 147) < 0.001)
    }

    @Test func emptyDayTotalsStayAtZero() {
        #expect(DiaryDay.totals(for: []) == DiaryDayTotals(
            eatenGrams: 0,
            wastedGrams: 0,
            eatenKilojoules: 0,
            wastedKilojoules: 0
        ))
    }

    @Test func wastedOnlyHidesRowsWithNoWaste() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDay = Date(timeIntervalSince1970: 900_000)
        let logs = [
            FoodLog(
                loggedAt: selectedDay,
                meal: .breakfast,
                foodName: "Eaten only",
                eatenGrams: 40,
                wastedGrams: 0,
                kilojoulesPer100g: 200
            ),
            FoodLog(
                loggedAt: selectedDay,
                meal: .lunch,
                foodName: "Wasted only",
                eatenGrams: 0,
                wastedGrams: 10,
                kilojoulesPer100g: 300
            ),
            FoodLog(
                loggedAt: selectedDay,
                meal: .dinner,
                foodName: "Both",
                eatenGrams: 20,
                wastedGrams: 5,
                kilojoulesPer100g: 400
            ),
            FoodLog(
                loggedAt: try #require(calendar.date(byAdding: .day, value: 1, to: selectedDay)),
                meal: .snacks,
                foodName: "Tomorrow",
                eatenGrams: 0,
                wastedGrams: 99,
                kilojoulesPer100g: 500
            ),
        ]

        let wasted = DiaryDay.filtered(
            logs,
            on: selectedDay,
            filter: .wasted,
            calendar: calendar
        )
        let eaten = DiaryDay.filtered(
            logs,
            on: selectedDay,
            filter: .eaten,
            calendar: calendar
        )

        #expect(wasted.map(\.foodName) == ["Wasted only", "Both"])
        #expect(wasted.allSatisfy { $0.wastedGrams > 0 })
        #expect(eaten.map(\.foodName) == ["Eaten only", "Both"])
    }
}
