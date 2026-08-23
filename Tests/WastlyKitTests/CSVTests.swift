import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct CSVTests {
    @Test func selectedKcalChangesExportPresentationNotStorage() {
        let log = FoodLog(
            loggedAt: Date(timeIntervalSince1970: 0),
            meal: .lunch,
            foodName: "Stored in kJ",
            eatenGrams: 100,
            wastedGrams: 0,
            kilojoulesPer100g: 4_184
        )

        let csv = DiaryCSV.build(logs: [log], unit: .kilocalories)

        #expect(DiaryCSV.headers(for: .kilocalories).suffix(2) == ["kcal eaten", "kcal wasted"])
        #expect(csv.hasPrefix("date,meal,food,eaten g,wasted g,kcal eaten,kcal wasted\n"))
        #expect(csv.contains(",1000.0,0.0\n"))
        #expect(log.kilojoulesPer100g == 4_184)
        #expect(log.eatenKilojoules == 4_184)
    }

    @Test func utf8ExportMatchesTheSpreadsheetContract() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))
        context.insert(child)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let loggedAt = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 22,
            hour: 12
        )))
        let log = FoodLog(
            loggedAt: loggedAt,
            meal: .breakfast,
            foodName: "Crème brûlée, \"small\"",
            eatenGrams: 30,
            wastedGrams: 10,
            kilojoulesPer100g: 1470,
            child: child
        )
        context.insert(log)
        try context.save()
        let csv = DiaryCSV.build(logs: [log])

        #expect(DiaryCSV.headers == [
            "date", "meal", "food", "eaten g", "wasted g", "kJ eaten", "kJ wasted"
        ])
        #expect(csv.hasPrefix("date,meal,food,eaten g,wasted g,kJ eaten,kJ wasted\n"))
        #expect(csv.contains("22/04/2026,breakfast,\"Crème brûlée, \"\"small\"\"\",30.0,10.0,441.0,147.0"))
        #expect(csv.contains("last name") == false)
        #expect(csv.contains("photo") == false)
        let data = Data(csv.utf8)
        #expect(String(data: data, encoding: .utf8) == csv)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WastlyCSVTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try DiaryCSV.write(
            logs: [log],
            to: directory,
            filename: "wastly-diary.csv"
        )
        #expect(file.pathExtension == "csv")
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == csv)
    }
}
