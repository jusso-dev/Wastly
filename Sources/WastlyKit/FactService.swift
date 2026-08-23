import Foundation
import CryptoKit

public struct FactTotals: Equatable, Sendable {
    public var days: Int
    public var eatenGrams: Double
    public var wastedGrams: Double
    public var eatenKilojoules: Double
    public var wastedKilojoules: Double
    public var topFood: String?

    public var wasteRatio: Double {
        let total = eatenGrams + wastedGrams
        guard total > 0 else { return 0 }
        return wastedGrams / total
    }

    public init(days: Int, eatenGrams: Double, wastedGrams: Double, eatenKilojoules: Double, wastedKilojoules: Double, topFood: String? = nil) {
        self.days = days
        self.eatenGrams = eatenGrams
        self.wastedGrams = wastedGrams
        self.eatenKilojoules = eatenKilojoules
        self.wastedKilojoules = wastedKilojoules
        self.topFood = topFood
    }

    public static func from(logs: [FoodLog], now: Date = .now) -> FactTotals {
        let eaten = logs.reduce(0) { $0 + $1.eatenGrams }
        let wasted = logs.reduce(0) { $0 + $1.wastedGrams }
        let eatenkJ = logs.reduce(0) { $0 + $1.eatenKilojoules }
        let wastedkJ = logs.reduce(0) { $0 + $1.wastedKilojoules }
        let days: Int = {
            guard let first = logs.map(\.loggedAt).min() else { return 0 }
            return max(1, Calendar.current.dateComponents([.day], from: first, to: now).day ?? 1)
        }()
        let top = Dictionary(grouping: logs, by: \.foodName)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.eatenGrams }) }
            .max { $0.1 < $1.1 }?.0
        return FactTotals(
            days: days,
            eatenGrams: eaten,
            wastedGrams: wasted,
            eatenKilojoules: eatenkJ,
            wastedKilojoules: wastedkJ,
            topFood: top
        )
    }

    public var inputsHash: String {
        let raw = "\(days)|\(eatenGrams)|\(wastedGrams)|\(topFood ?? "")"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum FactTemplates: Sendable {
    public static func fact(for totals: FactTotals, firstName: String? = nil) -> String {
        let who = firstName ?? "They"
        let food = totals.topFood ?? "food"
        if totals.eatenGrams + totals.wastedGrams < 1 {
            return "No logs yet. Add a meal and the facts will show up here."
        }
        if totals.wastedGrams < 40 {
            return "\(who) left a few bites of \(food) this week. About a lunchbox crumb, not a wheelie bin."
        }
        if totals.wastedGrams < 400 {
            return "\(who) wasted \(Int(totals.wastedGrams)) g this week, mostly \(food). That is a small lunchbox, not a wheelie bin."
        }
        if totals.wastedGrams < 4000 {
            return "\(who) wasted \(Int(totals.wastedGrams)) g this week. That would fill a lunchbox, not a wheelie bin."
        }
        return "\(who) wasted \(Int(totals.wastedGrams / 1000)) kg this week. Still not a stadium. Check the diary if that looks off."
    }

    public static func llmPayload(totals: FactTotals, firstName: String?) throws -> FactLLMPayload {
        let payload = FactLLMPayload(
            firstName: firstName,
            days: totals.days,
            eatenG: totals.eatenGrams,
            wastedG: totals.wastedGrams,
            topFood: totals.topFood
        )
        try PrivacyGuard.assertFactPayload(payload)
        return payload
    }
}

public enum FactRequestBuilder: Sendable {
    public static func make(
        url: URL,
        configuredHost: String,
        totals: FactTotals,
        firstName: String?
    ) throws -> URLRequest {
        guard PrivacyAllowlist.isAllowedLLMURL(url, configuredHosts: [configuredHost]) else {
            throw PrivacyError.disallowedDestination
        }
        let payload = try FactTemplates.llmPayload(totals: totals, firstName: firstName)
        let body = try JSONEncoder().encode(payload)
        try PrivacyGuard.assertFactJSON(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
