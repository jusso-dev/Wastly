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

    public static func isAllowedPlateMatchURL(_ url: URL, configuredHost: String) -> Bool {
        isSecure(url) && url.host?.caseInsensitiveCompare(configuredHost) == .orderedSame
    }

    private static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
    }
}

public enum PrivacyError: Error, Sendable {
    case forbiddenField(String)
    case disallowedDestination
}

public enum PrivacyGuard: Sendable {
    private static let personalProfileKeys: Set<String> = [
        "weightKg", "weightKilograms", "heightCm", "heightCentimetres",
        "photo", "photoJPEG", "dateOfBirth", "dob", "lastName",
    ]
    public static let forbiddenPlateKeys = personalProfileKeys.union([
        "child", "childId", "childID", "firstName", "name", "note",
    ])

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
