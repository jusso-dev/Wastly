import Foundation
import SwiftData
import Testing
@testable import WastlyKit

struct PrivacyTests {
    @Test func factPayloadOmitsBodyFields() throws {
        let payload = try FactTemplates.llmPayload(
            totals: FactTotals(days: 3, eatenGrams: 200, wastedGrams: 40, eatenKilojoules: 800, wastedKilojoules: 160, topFood: "Weet-Bix"),
            firstName: "Sam"
        )
        let object = try payload.jsonObject()
        #expect(Set(object.keys) == [
            "first_name", "days", "eaten_g", "wasted_g", "top_food",
        ])
        #expect(object["weightKg"] == nil)
        #expect(object["photo"] == nil)
        #expect(object["dateOfBirth"] == nil)
        try PrivacyGuard.assertFactPayload(payload)
    }

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

    @Test func addingPIIToOutboundJSONFailsTheGuard() throws {
        for object: [String: Any] in [
            ["firstName": "Sam", "weightKg": 18.0],
            ["first_name": "Sam", "child_metrics": ["weight_kg": 18.0]],
            ["child": ["photo": Data([0xFF, 0xD8]).base64EncodedString()]],
        ] {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: PrivacyError.self) {
                try PrivacyGuard.assertFactJSON(data)
            }
        }
    }

    @Test func factRequestRequiresConfiguredHTTPSHost() throws {
        let totals = FactTotals(
            days: 3,
            eatenGrams: 200,
            wastedGrams: 40,
            eatenKilojoules: 800,
            wastedKilojoules: 160,
            topFood: "Toast"
        )
        let allowed = URL(string: "https://facts.example/v1/fact")!
        let request = try FactRequestBuilder.make(
            url: allowed,
            configuredHost: "facts.example",
            totals: totals,
            firstName: nil
        )

        #expect(request.url == allowed)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody != nil)
        #expect(throws: PrivacyError.self) {
            try FactRequestBuilder.make(
                url: URL(string: "https://evil.example/v1/fact")!,
                configuredHost: "facts.example",
                totals: totals,
                firstName: nil
            )
        }
        #expect(throws: PrivacyError.self) {
            try FactRequestBuilder.make(
                url: URL(string: "http://facts.example/v1/fact")!,
                configuredHost: "facts.example",
                totals: totals,
                firstName: nil
            )
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
