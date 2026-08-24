import Foundation
import SwiftData

public actor LocalFoodStore {
    public static let defaultMaximumCatalogRows = 100_000

    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func inMemory() throws -> LocalFoodStore {
        let container = try WastlyContainer.make(inMemory: true)
        return LocalFoodStore(container: container)
    }

    func context() -> ModelContext {
        ModelContext(container)
    }

    public func searchLocal(_ query: String) -> [FoodHit] {
        let needle = query.lowercased()
        let ctx = context()
        let recents = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        let recentHits = recents
            .filter { $0.name.lowercased().contains(needle) || ($0.brand?.lowercased().contains(needle) ?? false) }
            .sorted { lhs, rhs in
                if lhs.isCustom != rhs.isCustom { return lhs.isCustom }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
            .map(Self.hit(fromCache:))

        let descriptor = FetchDescriptor<CatalogFood>(
            predicate: #Predicate { row in
                row.name.localizedStandardContains(query)
                    || (row.brand?.localizedStandardContains(query) ?? false)
            }
        )
        let catalogHits = ((try? ctx.fetch(descriptor)) ?? [])
            .filter {
                $0.name.lowercased().contains(needle)
                    || ($0.brand?.lowercased().contains(needle) ?? false)
            }
            .sorted { lhs, rhs in
                let lhsNameStartsWithQuery = lhs.name.lowercased().hasPrefix(needle)
                let rhsNameStartsWithQuery = rhs.name.lowercased().hasPrefix(needle)
                if lhsNameStartsWithQuery != rhsNameStartsWithQuery {
                    return lhsNameStartsWithQuery
                }

                let lhsBrandStartsWithQuery = lhs.brand?.lowercased().hasPrefix(needle) ?? false
                let rhsBrandStartsWithQuery = rhs.brand?.lowercased().hasPrefix(needle) ?? false
                if lhsBrandStartsWithQuery != rhsBrandStartsWithQuery {
                    return lhsBrandStartsWithQuery
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(100)
            .map(Self.hit(fromCatalog:))

        return FoodHitIdentity.merged(recentHits + catalogHits)
    }

    public func barcodeLocal(_ normalized: String) -> FoodHit? {
        let ctx = context()
        let recents = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        if let cache = recents.first(where: { $0.barcodeNormalized == normalized }) {
            return Self.hit(fromCache: cache)
        }
        var descriptor = FetchDescriptor<CatalogFood>(
            predicate: #Predicate { $0.barcodeNormalized == normalized }
        )
        descriptor.fetchLimit = 1
        if let row = try? ctx.fetch(descriptor).first {
            return Self.hit(fromCatalog: row)
        }
        return nil
    }

    public func cacheLookup(_ hit: FoodHit) {
        upsertCache(hit, isCustom: false, markUsed: false)
    }

    public func saveCustom(_ hit: FoodHit) {
        upsertCache(hit, isCustom: true, markUsed: false)
    }

    public func touchRecent(_ hit: FoodHit) {
        upsertCache(hit, isCustom: hit.origin == .custom, markUsed: true)
    }

    private func upsertCache(
        _ hit: FoodHit,
        isCustom: Bool,
        markUsed: Bool
    ) {
        let ctx = context()
        let existing = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        let key = FoodHitIdentity.key(for: hit)
        if let row = existing.first(where: {
            FoodHitIdentity.key(
                name: $0.name,
                brand: $0.brand,
                barcodeNormalized: $0.barcodeNormalized,
                providerKey: $0.providerKey ?? $0.id.uuidString
            ) == key || $0.providerKey == hit.id
        }) {
            // A provider result may de-duplicate against a user-authored food, but must never replace it.
            if !row.isCustom || isCustom {
                row.name = hit.name
                row.brand = hit.brand
                row.barcodeRaw = hit.barcodeRaw
                row.barcodeNormalized = hit.barcodeNormalized
                row.kilojoulesPer100g = hit.kilojoulesPer100g
                row.servingGrams = hit.servingGrams
                row.isCustom = isCustom || row.isCustom
            }
            if markUsed {
                row.useCount += 1
                row.lastUsedAt = .now
            }
        } else {
            ctx.insert(
                FoodCache(
                    name: hit.name,
                    brand: hit.brand,
                    barcodeRaw: hit.barcodeRaw,
                    kilojoulesPer100g: hit.kilojoulesPer100g,
                    servingGrams: hit.servingGrams,
                    origin: hit.origin,
                    isCustom: isCustom,
                    useCount: markUsed ? 1 : 0,
                    lastUsedAt: markUsed ? .now : .distantPast,
                    providerKey: hit.id
                )
            )
        }
        try? ctx.save()
    }

    @discardableResult
    public func clearCacheLeavingCustomAndLogs() throws -> Int {
        let ctx = context()
        let rows = try ctx.fetch(FetchDescriptor<FoodCache>())
        let removable = rows.filter { !$0.isCustom }
        for row in removable {
            ctx.delete(row)
        }
        try ctx.save()
        return removable.count
    }

    private static func hit(fromCache row: FoodCache) -> FoodHit {
        FoodHit(
            id: row.providerKey ?? row.id.uuidString,
            name: row.name,
            brand: row.brand,
            barcodeRaw: row.barcodeRaw,
            kilojoulesPer100g: row.kilojoulesPer100g,
            servingGrams: row.servingGrams,
            origin: FoodOrigin(rawValue: row.originRaw) ?? .recent
        )
    }

    private static func hit(fromCatalog row: CatalogFood) -> FoodHit {
        FoodHit(
            id: "catalog:\(row.barcodeNormalized)",
            name: row.name,
            brand: row.brand,
            barcodeRaw: row.barcodeRaw.isEmpty ? nil : row.barcodeRaw,
            kilojoulesPer100g: row.kilojoulesPer100g,
            servingGrams: row.servingGrams,
            origin: row.catalogVersion <= 0 ? .seed : .catalog
        )
    }
}
