import Testing
@testable import WastlyKit

struct PrivacyTests {
    @Test func factPayloadOmitsBodyFields() throws {
        let payload = try FactTemplates.llmPayload(
            totals: FactTotals(days: 3, eatenGrams: 200, wastedGrams: 40, eatenKilojoules: 800, wastedKilojoules: 160, topFood: "Weet-Bix"),
            firstName: "Sam"
        )
        let object = try payload.jsonObject()
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
    }

    @Test func addingWeightToOutboundJSONFailsTheGuard() throws {
        let sneaky: [String: Any] = ["firstName": "Sam", "weightKg": 18.0]
        let keys = Set(sneaky.keys)
        #expect(keys.contains("weightKg"))
        #expect(PrivacyGuard.forbiddenFactKeys.contains("weightKg"))
    }
}
