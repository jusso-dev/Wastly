import Foundation

public struct FactWeekDay: Equatable, Identifiable, Sendable {
    public var day: Date
    public var eatenGrams: Double
    public var wastedGrams: Double

    public var id: Date { day }

    public init(day: Date, eatenGrams: Double, wastedGrams: Double) {
        self.day = day
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
    }
}

public struct FactWeekSummary: Equatable, Sendable {
    public var days: [FactWeekDay]

    public var hasLogs: Bool {
        days.contains { $0.eatenGrams > 0 || $0.wastedGrams > 0 }
    }

    public var maximumGrams: Double {
        days.map { $0.eatenGrams + $0.wastedGrams }.max() ?? 0
    }

    public init(days: [FactWeekDay]) {
        self.days = days
    }

    public static func from(
        logs: [FoodLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FactWeekSummary {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { offset -> FactWeekDay? in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: today) else {
                return nil
            }
            let totals = DiaryDay.totals(for: DiaryDay.logs(logs, on: day, calendar: calendar))
            return FactWeekDay(
                day: day,
                eatenGrams: totals.eatenGrams,
                wastedGrams: totals.wastedGrams
            )
        }
        return FactWeekSummary(days: days)
    }

    public func barHeight(
        for grams: Double,
        maximumHeight: Double = 80,
        minimumVisibleHeight: Double = 4
    ) -> Double {
        guard grams > 0, maximumGrams > 0, maximumHeight > 0 else { return 0 }
        let floor = min(maximumHeight, max(0, minimumVisibleHeight))
        return min(maximumHeight, max(floor, maximumHeight * grams / maximumGrams))
    }
}
