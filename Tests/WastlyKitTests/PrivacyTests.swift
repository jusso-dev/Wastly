import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct PrivacyTests {
    @Test func plateMatchHasNoChildFields() {
        let request = PlateMatchRequest(jpegCrop: Data([0xFF, 0xD8]))
        let object = request.jsonObject()
        #expect(object["child"] == nil)
        #expect(object["firstName"] == nil)
        #expect(object["weightKg"] == nil)
    }

    @Test func allowlistRejectsRandomHost() {
        #expect(PrivacyAllowlist.isAllowedFoodHost("evil.example") == false)
        #expect(PrivacyAllowlist.isAllowedFoodHost("world.openfoodfacts.org"))
        #expect(PrivacyAllowlist.isAllowedFoodHost("api.nal.usda.gov"))
        #expect(PrivacyAllowlist.isAllowedFoodURL(URL(string: "http://world.openfoodfacts.org")!) == false)
        #expect(PrivacyAllowlist.isAllowedFoodURL(URL(string: "https://user@world.openfoodfacts.org")!) == false)
        #expect(PrivacyAllowlist.isAllowedFoodURL(URL(string: "https://world.openfoodfacts.org")!))
    }

    @Test func addingPIIToPlateJSONFailsTheGuard() throws {
        for object: [String: Any] in [
            ["firstName": "Sam", "weightKg": 18.0],
            ["first_name": "Sam", "child_metrics": ["weight_kg": 18.0]],
            ["child": ["photo": Data([0xFF, 0xD8]).base64EncodedString()]],
        ] {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: PrivacyError.self) {
                try PrivacyGuard.assertPlateJSON(data)
            }
        }
    }

    @Test func customLogCanBeWrittenWithoutLiveLookup() async throws {
        let container = try WastlyContainer.make(inMemory: true)
        let store = LocalFoodStore(container: container)
        let directory = LocalFirstFoodDirectory(store: store)
        let custom = FoodHit(
            id: "custom:toast",
            name: "Toast",
            kilojoulesPer100g: 1_100,
            origin: .custom
        )

        await directory.saveCustom(custom)
        let result = await directory.search("Toast", online: false)
        #expect(result.hits.first?.name == "Toast")

        let context = ModelContext(container)
        let child = Child(firstName: "Sam", dateOfBirth: .now)
        context.insert(child)
        context.insert(FoodLog(
            meal: .breakfast,
            foodName: custom.name,
            eatenGrams: 30,
            wastedGrams: 5,
            kilojoulesPer100g: custom.kilojoulesPer100g,
            child: child
        ))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<FoodLog>()).count == 1)
    }
}
