import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct CSVTests {
    @Test func headersMatchContract() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))
        context.insert(child)
        let log = FoodLog(
            loggedAt: Date(timeIntervalSince1970: 1_777_000_000),
            meal: .breakfast,
            foodName: "Weet-Bix",
            eatenGrams: 30,
            wastedGrams: 10,
            kilojoulesPer100g: 1470,
            child: child
        )
        context.insert(log)
        try context.save()
        let csv = DiaryCSV.build(logs: [log])
        #expect(csv.hasPrefix(DiaryCSV.headers.joined(separator: ",")))
        #expect(csv.contains("last name") == false)
        #expect(csv.contains("photo") == false)
        #expect(csv.contains("Weet-Bix"))
        #expect(csv.contains("breakfast"))
    }
}
