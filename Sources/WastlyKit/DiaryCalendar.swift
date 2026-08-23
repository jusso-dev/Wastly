import Foundation

public enum DiaryLogFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case eaten
    case wasted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .eaten:
            "Eaten only"
        case .wasted:
            "Wasted only"
        }
    }
}

public enum DiaryCalendarMode: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }
}

public struct DiaryCalendarDay: Equatable, Identifiable, Sendable {
    public var date: Date
    public var isInDisplayedMonth: Bool

    public var id: Date { date }

    public init(date: Date, isInDisplayedMonth: Bool) {
        self.date = date
        self.isInDisplayedMonth = isInDisplayedMonth
    }
}

public enum DiaryCalendar: Sendable {
    public static func days(
        containing selectedDate: Date,
        mode: DiaryCalendarMode,
        calendar: Calendar = .current
    ) -> [DiaryCalendarDay] {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        switch mode {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
                return []
            }
            return makeDays(
                from: interval.start,
                until: interval.end,
                selectedDate: selectedDay,
                calendar: calendar
            )
        case .month:
            guard let month = calendar.dateInterval(of: .month, for: selectedDay),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
                  let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
                  let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)
            else {
                return []
            }
            return makeDays(
                from: firstWeek.start,
                until: lastWeek.end,
                selectedDate: selectedDay,
                calendar: calendar
            )
        }
    }

    public static func movedDate(
        from date: Date,
        by offset: Int,
        mode: DiaryCalendarMode,
        calendar: Calendar = .current
    ) -> Date {
        let component: Calendar.Component = mode == .week ? .weekOfYear : .month
        return calendar.date(byAdding: component, value: offset, to: date) ?? date
    }

    private static func makeDays(
        from start: Date,
        until end: Date,
        selectedDate: Date,
        calendar: Calendar
    ) -> [DiaryCalendarDay] {
        var result: [DiaryCalendarDay] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            result.append(DiaryCalendarDay(
                date: day,
                isInDisplayedMonth: calendar.isDate(day, equalTo: selectedDate, toGranularity: .month)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                  next > day
            else {
                break
            }
            day = next
        }
        return result
    }
}
