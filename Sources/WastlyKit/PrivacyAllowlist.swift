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

    public static func isAllowedFoodURL(_ url: URL) -> Bool {
        isSecure(url) && isAllowedFoodHost(url.host ?? "")
    }

    public static func isAllowedCatalogURL(_ url: URL, extraHosts: Set<String> = []) -> Bool {
        guard isSecure(url), let host = url.host?.lowercased() else { return false }
        if isAllowedFoodHost(host) { return true }
        return Set(extraHosts.map { $0.lowercased() }).contains(host)
    }

    public static func isAllowedLLMHost(_ host: String, configured: Set<String>) -> Bool {
        Set(configured.map { $0.lowercased() }).contains(host.lowercased())
    }

    public static func isAllowedLLMURL(_ url: URL, configuredHosts: Set<String>) -> Bool {
        isSecure(url) && isAllowedLLMHost(url.host ?? "", configured: configuredHosts)
    }

    public static func isAllowedPlateMatchURL(_ url: URL, configuredHost: String) -> Bool {
        isSecure(url) && url.host?.caseInsensitiveCompare(configuredHost) == .orderedSame
    }

    private static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
    }
}

/// The only fields a facts LLM may receive.
public struct FactLLMPayload: Codable, Equatable, Sendable {
    public var firstName: String?
    public var days: Int
    public var eatenG: Double
    public var wastedG: Double
    public var topFood: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case days
        case eatenG = "eaten_g"
        case wastedG = "wasted_g"
        case topFood = "top_food"
    }

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
    case disallowedDestination
}

public enum PrivacyGuard: Sendable {
    public static let forbiddenFactKeys: Set<String> = [
        "weightKg", "weightKilograms", "heightCm", "heightCentimetres",
        "photo", "photoJPEG", "dateOfBirth", "dob", "lastName",
    ]
    public static let forbiddenPlateKeys = forbiddenFactKeys.union([
        "child", "childId", "childID", "firstName", "name", "note",
    ])

    public static func assertFactPayload(_ payload: FactLLMPayload) throws {
        try assertFactJSON(JSONEncoder().encode(payload))
    }

    public static func assertFactJSON(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        try assertNoForbiddenFields(in: object, forbiddenKeys: forbiddenFactKeys)
    }

    public static func assertPlateJSON(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        try assertNoForbiddenFields(in: object, forbiddenKeys: forbiddenPlateKeys)
    }

    private static func assertNoForbiddenFields(
        in value: Any,
        forbiddenKeys: Set<String>
    ) throws {
        try assertNoForbiddenFields(
            in: value,
            normalizedForbiddenKeys: Set(forbiddenKeys.map(normalizedKey))
        )
    }

    private static func assertNoForbiddenFields(
        in value: Any,
        normalizedForbiddenKeys: Set<String>
    ) throws {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                if normalizedForbiddenKeys.contains(normalizedKey(key)) {
                    throw PrivacyError.forbiddenField(key)
                }
                try assertNoForbiddenFields(
                    in: child,
                    normalizedForbiddenKeys: normalizedForbiddenKeys
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                try assertNoForbiddenFields(
                    in: child,
                    normalizedForbiddenKeys: normalizedForbiddenKeys
                )
            }
        }
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
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

    public func encodedJSON() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: jsonObject(), options: [.sortedKeys])
        try PrivacyGuard.assertPlateJSON(data)
        return data
    }
}
