import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct OnboardingTests {
    @Test func savesRequiredChildOptionalMeasurementAndSettings() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)
        let dateOfBirth = Date(timeIntervalSince1970: 1_650_000_000)

        let child = try OnboardingStore.save(
            OnboardingInput(
                firstName: "  Sam  ",
                dateOfBirth: dateOfBirth,
                heightCentimetres: 104,
                weightKilograms: 17.5,
                faceIDEnabled: true,
                iCloudBackupEnabled: true,
                backupPasswordEnabled: true
            ),
            in: context
        )

        let children = try context.fetch(FetchDescriptor<Child>())
        let measurements = try context.fetch(FetchDescriptor<MeasurementPoint>())
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(children.map(\.id) == [child.id])
        #expect(children.first?.firstName == "Sam")
        #expect(children.first?.dateOfBirth == dateOfBirth)
        #expect(measurements.first?.heightCentimetres == 104)
        #expect(measurements.first?.weightKilograms == 17.5)
        #expect(settings.faceIDEnabled)
        #expect(settings.iCloudBackupEnabled)
        #expect(settings.backupPasswordEnabled)
    }

    @Test func secondContainerFetchesSavedChild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WastlyOnboardingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Wastly.store")

        do {
            let container = try WastlyContainer.make(url: storeURL)
            let context = ModelContext(container)
            try OnboardingStore.save(
                OnboardingInput(firstName: "Sam", dateOfBirth: .now),
                in: context
            )
        }

        let reopened = try WastlyContainer.make(url: storeURL)
        let children = try ModelContext(reopened).fetch(FetchDescriptor<Child>())
        #expect(children.count == 1)
        #expect(children.first?.firstName == "Sam")
    }

    @Test func blankNameDoesNotInsertAChild() throws {
        let container = try WastlyContainer.make(inMemory: true)
        let context = ModelContext(container)

        #expect(throws: OnboardingError.self) {
            try OnboardingStore.save(
                OnboardingInput(firstName: "   ", dateOfBirth: .now),
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<Child>()).isEmpty)
    }
}
