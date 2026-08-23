import Foundation
import SwiftData

public actor LocalFoodStore {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func inMemory() throws -> LocalFoodStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(WastlySchema.models), configurations: config)
        return LocalFoodStore(container: container)
    }

    private func context() -> ModelContext {
        ModelContext(container)
    }

    public func searchLocal(_ query: String) -> [FoodHit] {
        let needle = query.lowercased()
        let ctx = context()
        let recents = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        let recentHits = recents
            .filter { $0.name.lowercased().contains(needle) || ($0.brand?.lowercased().contains(needle) ?? false) }
            .sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
            .map(Self.hit(fromCache:))

        let catalog = (try? ctx.fetch(FetchDescriptor<CatalogFood>())) ?? []
        let catalogHits = catalog
            .filter { $0.name.lowercased().contains(needle) || ($0.brand?.lowercased().contains(needle) ?? false) }
            .map(Self.hit(fromCatalog:))

        var seen = Set<String>()
        var merged: [FoodHit] = []
        for hit in recentHits + catalogHits {
            let key = hit.barcodeNormalized ?? hit.id
            if seen.insert(key).inserted { merged.append(hit) }
        }
        return merged
    }

    public func barcodeLocal(_ normalized: String) -> FoodHit? {
        let ctx = context()
        let recents = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        if let cache = recents.first(where: { $0.barcodeNormalized == normalized }) {
            return Self.hit(fromCache: cache)
        }
        let catalog = (try? ctx.fetch(FetchDescriptor<CatalogFood>())) ?? []
        if let row = catalog.first(where: { $0.barcodeNormalized == normalized }) {
            return Self.hit(fromCatalog: row)
        }
        return nil
    }

    public func upsertCache(_ hit: FoodHit, isCustom: Bool = false) {
        let ctx = context()
        let existing = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        let key = hit.barcodeNormalized ?? hit.id
        if let row = existing.first(where: { ($0.barcodeNormalized ?? $0.providerKey) == key || $0.providerKey == hit.id }) {
            row.name = hit.name
            row.brand = hit.brand
            row.barcodeRaw = hit.barcodeRaw
            row.barcodeNormalized = hit.barcodeNormalized
            row.kilojoulesPer100g = hit.kilojoulesPer100g
            row.servingGrams = hit.servingGrams
            row.isCustom = isCustom || row.isCustom
            row.useCount += 1
            row.lastUsedAt = .now
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
                    providerKey: hit.id
                )
            )
        }
        try? ctx.save()
    }

    public func touchRecent(_ hit: FoodHit) {
        upsertCache(hit)
    }

    public func upsertCatalog(_ rows: [SeedFood], version: Int) {
        let ctx = context()
        let existing = (try? ctx.fetch(FetchDescriptor<CatalogFood>())) ?? []
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.barcodeNormalized, $0) })
        for row in rows {
            let key = Barcode.normalized(row.barcode)
            guard !key.isEmpty else { continue }
            if let found = byKey[key] {
                found.name = row.name
                found.brand = row.brand
                found.barcodeRaw = row.barcode
                found.kilojoulesPer100g = row.kilojoulesPer100g
                found.servingGrams = row.servingGrams
                found.catalogVersion = version
                found.updatedAt = .now
            } else {
                let food = CatalogFood(
                    barcodeRaw: row.barcode,
                    name: row.name,
                    brand: row.brand,
                    kilojoulesPer100g: row.kilojoulesPer100g,
                    servingGrams: row.servingGrams,
                    catalogVersion: version
                )
                ctx.insert(food)
                byKey[key] = food
            }
        }
        try? ctx.save()
    }

    public func clearCacheLeavingCustomAndLogs() {
        let ctx = context()
        let rows = (try? ctx.fetch(FetchDescriptor<FoodCache>())) ?? []
        for row in rows where !row.isCustom {
            ctx.delete(row)
        }
        try? ctx.save()
    }

    public func insertSeedIfEmpty() {
        let ctx = context()
        let count = (try? ctx.fetchCount(FetchDescriptor<CatalogFood>())) ?? 0
        guard count == 0 else { return }
        upsertCatalog(SeedCatalog.foods, version: 0)
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
            barcodeRaw: row.barcodeRaw,
            kilojoulesPer100g: row.kilojoulesPer100g,
            servingGrams: row.servingGrams,
            origin: row.catalogVersion == 0 ? .seed : .catalog
        )
    }
}
