import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct ModelTests {
    @Test func childAndLogRoundTrip() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_200_000_000))
        context.insert(child)
        let log = FoodLog(
            meal: .breakfast,
            foodName: "Weet-Bix",
            eatenGrams: 30,
            wastedGrams: 10,
            kilojoulesPer100g: 1470,
            child: child
        )
        context.insert(log)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Child>())
        #expect(fetched.count == 1)
        #expect(fetched[0].logs.count == 1)
        #expect(abs(fetched[0].logs[0].eatenKilojoules - 441) < 0.01)
    }

    @Test func deletingChildCascadesLogs() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        context.insert(FoodLog(meal: .lunch, foodName: "Apple", eatenGrams: 50, wastedGrams: 0, kilojoulesPer100g: 218, child: child))
        try context.save()
        context.delete(child)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<FoodLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)
    }
}
