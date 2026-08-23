import CryptoKit
import Foundation

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

    public static func from(
        logs: [FoodLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FactTotals {
        let eaten = logs.reduce(0) { $0 + $1.eatenGrams }
        let wasted = logs.reduce(0) { $0 + $1.wastedGrams }
        let eatenkJ = logs.reduce(0) { $0 + $1.eatenKilojoules }
        let wastedkJ = logs.reduce(0) { $0 + $1.wastedKilojoules }
        let days: Int = {
            guard let first = logs.map(\.loggedAt).min() else { return 0 }
            let firstDay = calendar.startOfDay(for: first)
            let currentDay = calendar.startOfDay(for: now)
            let elapsedDays = calendar.dateComponents([.day], from: firstDay, to: currentDay).day ?? 0
            return max(1, elapsedDays + 1)
        }()
        let top = Dictionary(grouping: logs, by: \.foodName)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.eatenGrams }) }
            .sorted { left, right in
                if left.1 == right.1 { return left.0 < right.0 }
                return left.1 > right.1
            }
            .first?.0
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
        let raw = [
            "v2",
            String(days),
            String(Self.materialBucket(eatenGrams, step: 250)),
            String(Self.materialBucket(wastedGrams, step: 250)),
            String(Self.materialBucket(eatenKilojoules, step: 500)),
            String(Self.materialBucket(wastedKilojoules, step: 500)),
            topFood?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func materialBucket(_ value: Double, step: Double) -> Int {
        guard value.isFinite else { return 0 }
        let scaled = (max(0, value) / step).rounded()
        guard scaled < Double(Int.max) else { return Int.max }
        return Int(scaled)
    }
}

public enum FactScale: String, CaseIterable, Sendable {
    case bites
    case lunchbox
    case footy
    case wheelieBin
    case mcg

    public static func pick(forWastedGrams grams: Double) -> FactScale {
        switch max(0, grams) {
        case ..<40:
            return .bites
        case ..<500:
            return .lunchbox
        case ..<20_000:
            return .footy
        case ..<50_000_000:
            return .wheelieBin
        default:
            return .mcg
        }
    }
}

public enum FactCachePolicy: Sendable {
    public static func shouldRegenerate(
        cachedInputsHash: String?,
        cachedAt: Date?,
        totals: FactTotals,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let cachedInputsHash, let cachedAt else { return true }
        guard calendar.isDate(cachedAt, inSameDayAs: now) else { return true }
        return cachedInputsHash != totals.inputsHash
    }
}

public enum FactTemplates: Sendable {
    public static func fact(for totals: FactTotals, firstName: String? = nil) -> String {
        let who = firstName ?? "They"
        if totals.eatenGrams + totals.wastedGrams < 1 {
            return "No logs yet. Add a meal and the facts will show up here."
        }

        let dayCount = max(1, totals.days)
        let period = dayCount == 1 ? "one logged day" : "\(dayCount) logged days"
        let topFood = totals.topFood.map { " \($0) was the top food by eaten amount." } ?? ""
        if totals.wastedGrams < 1 {
            return "\(who) recorded \(Int(totals.eatenGrams.rounded())) g eaten across \(period), with no food left.\(topFood)"
        }

        let wastedGrams = max(0, totals.wastedGrams)
        let wastePercent = Int((totals.wasteRatio * 100).rounded())
        let summary = "\(who) recorded \(Int(wastedGrams.rounded())) g left across \(period) (\(wastePercent)% of logged food).\(topFood)"

        switch FactScale.pick(forWastedGrams: wastedGrams) {
        case .bites:
            return "\(summary) That is only a few bites—small lunchbox scale."
        case .lunchbox:
            return "\(summary) That is less than two 400 g lunchbox portions."
        case .footy:
            let count = max(1, Int((wastedGrams / 500).rounded()))
            let noun = count == 1 ? "footy" : "footies"
            return "\(summary) That is about \(count) 500 g \(noun) by weight."
        case .wheelieBin:
            let count = max(1, Int((wastedGrams / 20_000).rounded()))
            let noun = count == 1 ? "load" : "loads"
            return "\(summary) That is about \(count) 20 kg wheelie-bin \(noun) by weight."
        case .mcg:
            return "\(summary) At 500 g per portion, that is at least 100,000 portions—finally large enough for an MCG-scale comparison."
        }
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
