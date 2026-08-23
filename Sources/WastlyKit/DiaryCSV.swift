import Foundation

public enum DiaryCSV: Sendable {
    public static let headers = ["date", "meal", "food", "eaten g", "wasted g", "kJ eaten", "kJ wasted"]

    public static func build(logs: [FoodLog], timeZone: TimeZone = TimeZone(identifier: "Australia/Sydney") ?? .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "dd/MM/yyyy"
        var lines = [headers.joined(separator: ",")]
        for log in logs.sorted(by: { $0.loggedAt < $1.loggedAt }) {
            let cols = [
                formatter.string(from: log.loggedAt),
                csv(log.meal.rawValue),
                csv(log.foodName),
                csv(format(log.eatenGrams)),
                csv(format(log.wastedGrams)),
                csv(format(log.eatenKilojoules)),
                csv(format(log.wastedKilojoules)),
            ]
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    public static func write(
        logs: [FoodLog],
        to directory: URL,
        filename: String,
        timeZone: TimeZone = TimeZone(identifier: "Australia/Sydney") ?? .current
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename)
        try Data(build(logs: logs, timeZone: timeZone).utf8)
            .write(to: url, options: .atomic)
        return url
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_AU"), value)
    }

    private static func csv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
