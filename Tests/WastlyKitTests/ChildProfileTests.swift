import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct ChildProfileTests {
    @Test func twoChildrenKeepIndependentDiariesAndMeasurementHistory() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let firstMeasurementDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondMeasurementDate = Date(timeIntervalSince1970: 1_710_000_000)

        let sam = try ChildProfileStore.create(
            ChildProfileInput(firstName: "Sam", dateOfBirth: Date(timeIntervalSince1970: 1_600_000_000)),
            initialMeasurement: ChildMeasurementInput(
                recordedAt: firstMeasurementDate,
                heightCentimetres: 104,
                weightKilograms: 17.5
            ),
            in: context
        )
        let alex = try ChildProfileStore.create(
            ChildProfileInput(firstName: "Alex", dateOfBirth: Date(timeIntervalSince1970: 1_610_000_000)),
            in: context
        )

        let samLog = FoodLog(
            meal: .breakfast,
            foodName: "Toast",
            eatenGrams: 40,
            wastedGrams: 5,
            kilojoulesPer100g: 1_000,
            child: sam
        )
        let alexLog = FoodLog(
            meal: .lunch,
            foodName: "Apple",
            eatenGrams: 80,
            wastedGrams: 0,
            kilojoulesPer100g: 218,
            child: alex
        )
        context.insert(samLog)
        context.insert(alexLog)
        try context.save()

        try ChildProfileStore.update(
            sam,
            with: ChildProfileInput(
                firstName: "  Sammy  ",
                dateOfBirth: sam.dateOfBirth,
                photoJPEG: Data([0x01, 0x02])
            ),
            newMeasurement: ChildMeasurementInput(
                recordedAt: secondMeasurementDate,
                heightCentimetres: 107
            ),
            in: context
        )

        let allLogs = try context.fetch(FetchDescriptor<FoodLog>())
        #expect(ChildSelection.logs(for: sam.id, from: allLogs).map(\.foodName) == ["Toast"])
        #expect(ChildSelection.logs(for: alex.id, from: allLogs).map(\.foodName) == ["Apple"])
        #expect(sam.firstName == "Sammy")
        #expect(sam.photoJPEG == Data([0x01, 0x02]))

        let samMeasurements = try context.fetch(FetchDescriptor<MeasurementPoint>())
            .filter { $0.child?.id == sam.id }
            .sorted { $0.recordedAt < $1.recordedAt }
        #expect(samMeasurements.count == 2)
        #expect(samMeasurements.map(\.recordedAt) == [firstMeasurementDate, secondMeasurementDate])
        #expect(samMeasurements[1].heightCentimetres == 107)
        #expect(samMeasurements[1].weightKilograms == nil)
    }

    @Test func switcherOnlyShowsForMultipleChildren() {
        #expect(!ChildSelection.showsSwitcher(childCount: 0))
        #expect(!ChildSelection.showsSwitcher(childCount: 1))
        #expect(ChildSelection.showsSwitcher(childCount: 2))
    }

    @Test func deletingOneChildLeavesTheOtherDiaryUntouched() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let sam = try ChildProfileStore.create(
            ChildProfileInput(firstName: "Sam", dateOfBirth: .now),
            initialMeasurement: ChildMeasurementInput(heightCentimetres: 104),
            in: context
        )
        let alex = try ChildProfileStore.create(
            ChildProfileInput(firstName: "Alex", dateOfBirth: .now),
            in: context
        )
        context.insert(FoodLog(
            meal: .lunch,
            foodName: "Sam’s lunch",
            eatenGrams: 50,
            wastedGrams: 0,
            kilojoulesPer100g: 200,
            child: sam
        ))
        context.insert(FoodLog(
            meal: .lunch,
            foodName: "Alex’s lunch",
            eatenGrams: 60,
            wastedGrams: 0,
            kilojoulesPer100g: 200,
            child: alex
        ))
        try context.save()

        try ChildProfileStore.delete(sam, in: context)

        let children = try context.fetch(FetchDescriptor<Child>())
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        let measurements = try context.fetch(FetchDescriptor<MeasurementPoint>())
        #expect(children.map(\.id) == [alex.id])
        #expect(logs.map(\.foodName) == ["Alex’s lunch"])
        #expect(measurements.isEmpty)
    }

    @Test func invalidProfileAndMeasurementDoNotPersist() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)

        #expect(throws: ChildProfileError.self) {
            try ChildProfileStore.create(
                ChildProfileInput(firstName: "   ", dateOfBirth: .now),
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)

        let child = try ChildProfileStore.create(
            ChildProfileInput(firstName: "Sam", dateOfBirth: .now),
            in: context
        )
        #expect(throws: ChildProfileError.self) {
            try ChildProfileStore.addMeasurement(
                ChildMeasurementInput(weightKilograms: -1),
                to: child,
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<MeasurementPoint>()).isEmpty)
    }
}
