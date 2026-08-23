import Foundation

public struct DiaryDayTotals: Equatable, Sendable {
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var eatenKilojoules: Double
    public var wastedKilojoules: Double

    public init(
        eatenGrams: Double,
        wastedGrams: Double,
        eatenKilojoules: Double,
        wastedKilojoules: Double
    ) {
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
        self.eatenKilojoules = eatenKilojoules
        self.wastedKilojoules = wastedKilojoules
    }
}

public enum DiaryDay: Sendable {
    public static func logs(
        _ logs: [FoodLog],
        on day: Date,
        calendar: Calendar = .current
    ) -> [FoodLog] {
        logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
    }

    public static func totals(for logs: [FoodLog]) -> DiaryDayTotals {
        DiaryDayTotals(
            eatenGrams: logs.reduce(0) { $0 + $1.eatenGrams },
            wastedGrams: logs.reduce(0) { $0 + $1.wastedGrams },
            eatenKilojoules: logs.reduce(0) { $0 + $1.eatenKilojoules },
            wastedKilojoules: logs.reduce(0) { $0 + $1.wastedKilojoules }
        )
    }
}
