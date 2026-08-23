import Foundation

public enum PrivacyAllowlist: Sendable {
    public static let openFoodFactsHosts: Set<String> = [
        "world.openfoodfacts.org",
        "world.openfoodfacts.net",
    ]

    public static let usdaHosts: Set<String> = [
        "api.nal.usda.gov",
        "fdc.nal.usda.gov",
    ]

    public static func isAllowedFoodHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return openFoodFactsHosts.contains(lower) || usdaHosts.contains(lower)
    }

    public static func isAllowedCatalogURL(_ url: URL, extraHosts: Set<String> = []) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if isAllowedFoodHost(host) { return true }
        return extraHosts.contains(host)
    }

    public static func isAllowedLLMHost(_ host: String, configured: Set<String>) -> Bool {
        configured.contains(host.lowercased())
    }
}

/// The only fields a facts LLM may receive.
public struct FactLLMPayload: Codable, Equatable, Sendable {
    public var firstName: String?
    public var days: Int
    public var eatenG: Double
    public var wastedG: Double
    public var topFood: String?

    public init(firstName: String? = nil, days: Int, eatenG: Double, wastedG: Double, topFood: String? = nil) {
        self.firstName = firstName
        self.days = days
        self.eatenG = eatenG
        self.wastedG = wastedG
        self.topFood = topFood
    }

    public func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw PrivacyError.unexpectedPayload
        }
        return dict
    }
}

public enum PrivacyError: Error, Sendable {
    case unexpectedPayload
    case forbiddenField(String)
}

public enum PrivacyGuard: Sendable {
    public static let forbiddenFactKeys: Set<String> = [
        "weightKg", "weightKilograms", "heightCm", "heightCentimetres",
        "photo", "photoJPEG", "dateOfBirth", "dob", "lastName",
    ]

    public static func assertFactPayload(_ payload: FactLLMPayload) throws {
        let object = try payload.jsonObject()
        for key in object.keys where forbiddenFactKeys.contains(key) {
            throw PrivacyError.forbiddenField(key)
        }
    }
}

public struct PlateMatchRequest: Sendable {
    public var jpegCrop: Data
    public var mimeType: String

    public init(jpegCrop: Data, mimeType: String = "image/jpeg") {
        self.jpegCrop = jpegCrop
        self.mimeType = mimeType
    }

    public func jsonObject() -> [String: Any] {
        [
            "image": jpegCrop.base64EncodedString(),
            "mimeType": mimeType,
        ]
    }
}
