import Foundation
import Testing
@testable import WastlyKit

struct DiaryCalendarTests {
    @Test func weekContainsSevenDaysStartingOnConfiguredFirstWeekday() throws {
        let selected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 12
        )))

        let days = DiaryCalendar.days(
            containing: selected,
            mode: .week,
            calendar: calendar
        )

        #expect(days.count == 7)
        #expect(calendar.component(.weekday, from: try #require(days.first?.date)) == 2)
        #expect(calendar.isDate(try #require(days.last?.date), inSameDayAs: try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))
        )))
    }

    @Test func monthIncludesCompleteWeeksAndMarksOutsideDays() throws {
        let selected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19
        )))

        let days = DiaryCalendar.days(
            containing: selected,
            mode: .month,
            calendar: calendar
        )

        #expect(days.count == 42)
        #expect(calendar.component(.month, from: try #require(days.first?.date)) == 7)
        #expect(calendar.component(.day, from: try #require(days.first?.date)) == 27)
        #expect(calendar.component(.month, from: try #require(days.last?.date)) == 9)
        #expect(calendar.component(.day, from: try #require(days.last?.date)) == 6)
        #expect(days.filter(\.isInDisplayedMonth).count == 31)
    }

    @Test func arrowsMoveByTheVisibleRange() throws {
        let selected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19
        )))
        let nextWeek = DiaryCalendar.movedDate(
            from: selected,
            by: 1,
            mode: .week,
            calendar: calendar
        )
        let nextMonth = DiaryCalendar.movedDate(
            from: selected,
            by: 1,
            mode: .month,
            calendar: calendar
        )

        #expect(calendar.component(.day, from: nextWeek) == 26)
        #expect(calendar.component(.month, from: nextMonth) == 9)
        #expect(calendar.component(.day, from: nextMonth) == 19)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}
