import Foundation
import SwiftData

public struct CatalogStorageSnapshot: Equatable, Sendable {
    public var version: Int
    public var etag: String?
    public var lastSuccessAt: Date?
    public var lastError: String?
    public var rowCount: Int
    public var estimatedBytes: Int

    public init(
        version: Int = 0,
        etag: String? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        rowCount: Int = 0,
        estimatedBytes: Int = 0
    ) {
        self.version = version
        self.etag = etag
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.rowCount = rowCount
        self.estimatedBytes = estimatedBytes
    }
}

public struct CatalogClearResult: Equatable, Sendable {
    public var downloadedRows: Int
    public var lookupCacheRows: Int
    public var snapshot: CatalogStorageSnapshot

    public init(
        downloadedRows: Int,
        lookupCacheRows: Int,
        snapshot: CatalogStorageSnapshot
    ) {
        self.downloadedRows = downloadedRows
        self.lookupCacheRows = lookupCacheRows
        self.snapshot = snapshot
    }
}

public enum CatalogStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidFood(String)
    case rowLimitExceeded(limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidFood(reason):
            "The catalog contains an invalid food row: \(reason)."
        case let .rowLimitExceeded(limit):
            "The catalog exceeds Wastly’s \(limit.formatted())-food storage limit."
        }
    }
}

private struct CatalogWriteConfiguration {
    var version: Int
    var updatedAt: Date
    var maximumRows: Int
}

private enum CatalogFieldLimit {
    static let barcodeBytes = 64
    static let nameBytes = 200
    static let brandBytes = 200
}

extension LocalFoodStore {
    public func upsertCatalog(
        _ rows: [SeedFood],
        version: Int,
        maximumRows: Int = defaultMaximumCatalogRows
    ) throws {
        let context = context()
        let existing = (try? context.fetch(FetchDescriptor<CatalogFood>())) ?? []
        try upsertCatalogRows(
            rows,
            configuration: CatalogWriteConfiguration(
                version: version,
                updatedAt: .now,
                maximumRows: maximumRows
            ),
            existing: existing,
            in: context
        )
        try context.save()
    }

    @discardableResult
    public func commitCatalog(
        _ rows: [SeedFood],
        version: Int,
        etag: String?,
        syncedAt: Date = .now,
        maximumRows: Int = defaultMaximumCatalogRows
    ) throws -> CatalogStorageSnapshot {
        let context = context()
        let existing = try context.fetch(FetchDescriptor<CatalogFood>())
        try upsertCatalogRows(
            rows,
            configuration: CatalogWriteConfiguration(
                version: version,
                updatedAt: syncedAt,
                maximumRows: maximumRows
            ),
            existing: existing,
            in: context
        )

        let state = catalogState(in: context)
        state.catalogVersion = version
        state.etag = etag
        state.lastSuccessAt = syncedAt
        state.lastError = nil

        let metrics = Self.metrics(for: try context.fetch(FetchDescriptor<CatalogFood>()))
        let settings = appSettings(in: context)
        settings.lastCatalogSyncAt = syncedAt
        settings.catalogBytesOnDisk = metrics.estimatedBytes
        try context.save()

        return CatalogStorageSnapshot(
            version: version,
            etag: etag,
            lastSuccessAt: syncedAt,
            rowCount: metrics.rowCount,
            estimatedBytes: metrics.estimatedBytes
        )
    }

    public func catalogSnapshot() -> CatalogStorageSnapshot {
        let context = context()
        let foods = (try? context.fetch(FetchDescriptor<CatalogFood>())) ?? []
        let metrics = Self.metrics(for: foods)
        let state = (try? context.fetch(FetchDescriptor<CatalogState>()))?.first
        return CatalogStorageSnapshot(
            version: state?.catalogVersion ?? 0,
            etag: state?.etag,
            lastSuccessAt: state?.lastSuccessAt,
            lastError: state?.lastError,
            rowCount: metrics.rowCount,
            estimatedBytes: metrics.estimatedBytes
        )
    }

    public func recordCatalogFailure(_ message: String) {
        let context = context()
        let state = catalogState(in: context)
        state.lastError = message
        try? context.save()
    }

    public func recordCatalogNotModified(
        etag: String?,
        checkedAt: Date
    ) -> CatalogStorageSnapshot {
        let context = context()
        let state = catalogState(in: context)
        state.etag = etag
        state.lastSuccessAt = checkedAt
        state.lastError = nil
        let foods = (try? context.fetch(FetchDescriptor<CatalogFood>())) ?? []
        let metrics = Self.metrics(for: foods)
        let settings = appSettings(in: context)
        settings.lastCatalogSyncAt = checkedAt
        settings.catalogBytesOnDisk = metrics.estimatedBytes
        try? context.save()
        return CatalogStorageSnapshot(
            version: state.catalogVersion,
            etag: etag,
            lastSuccessAt: checkedAt,
            rowCount: metrics.rowCount,
            estimatedBytes: metrics.estimatedBytes
        )
    }

    public func insertSeedIfEmpty() throws {
        let context = context()
        let count = (try? context.fetchCount(FetchDescriptor<CatalogFood>())) ?? 0
        guard count == 0 else { return }
        try upsertCatalogRows(
            SeedCatalog.foods,
            configuration: CatalogWriteConfiguration(
                version: 0,
                updatedAt: .now,
                maximumRows: Self.defaultMaximumCatalogRows
            ),
            existing: [],
            in: context
        )
        try context.save()
    }

    public func clearDownloadedCatalogLeavingSeedCustomAndLogs() throws -> CatalogClearResult {
        let context = context()
        let catalogRows = try context.fetch(FetchDescriptor<CatalogFood>())
        let downloaded = catalogRows.filter { $0.catalogVersion > 0 }
        let retainedSeedRows = restoreSeedRows(from: catalogRows, in: context)

        let cacheRows = try context.fetch(FetchDescriptor<FoodCache>())
        let downloadedCache = cacheRows.filter { !$0.isCustom }
        for row in downloadedCache { context.delete(row) }

        try upsertCatalogRows(
            SeedCatalog.foods,
            configuration: CatalogWriteConfiguration(
                version: 0,
                updatedAt: .now,
                maximumRows: Self.defaultMaximumCatalogRows
            ),
            existing: retainedSeedRows,
            in: context
        )
        resetCatalogState(in: context)
        try context.save()

        return CatalogClearResult(
            downloadedRows: downloaded.count,
            lookupCacheRows: downloadedCache.count,
            snapshot: catalogSnapshot()
        )
    }

    private func restoreSeedRows(
        from catalogRows: [CatalogFood],
        in context: ModelContext
    ) -> [CatalogFood] {
        let seedsByBarcode = Dictionary(
            uniqueKeysWithValues: SeedCatalog.foods.map {
                (Barcode.normalized($0.barcode), $0)
            }
        )
        var retained: [CatalogFood] = []
        for row in catalogRows {
            guard let seed = seedsByBarcode[row.barcodeNormalized] else {
                context.delete(row)
                continue
            }
            apply(seed, to: row, version: 0, updatedAt: .now)
            retained.append(row)
        }
        return retained
    }

    private func resetCatalogState(in context: ModelContext) {
        let state = catalogState(in: context)
        state.catalogVersion = 0
        state.etag = nil
        state.lastSuccessAt = nil
        state.lastError = nil

        let settings = appSettings(in: context)
        settings.lastCatalogSyncAt = nil
        settings.catalogBytesOnDisk = Self.metricsForSeedRows(SeedCatalog.foods).estimatedBytes
    }

    private func upsertCatalogRows(
        _ rows: [SeedFood],
        configuration: CatalogWriteConfiguration,
        existing: [CatalogFood],
        in context: ModelContext
    ) throws {
        let incoming = try sanitizedRows(rows)
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.barcodeNormalized, $0) })
        let addedCount = incoming.keys.filter { byKey[$0] == nil }.count
        guard existing.count + addedCount <= configuration.maximumRows else {
            throw CatalogStoreError.rowLimitExceeded(limit: configuration.maximumRows)
        }

        for (key, row) in incoming {
            if let found = byKey[key] {
                apply(row, to: found, version: configuration.version, updatedAt: configuration.updatedAt)
            } else {
                let food = CatalogFood(
                    barcodeRaw: row.barcode,
                    name: row.name,
                    brand: row.brand,
                    kilojoulesPer100g: row.kilojoulesPer100g,
                    servingGrams: row.servingGrams,
                    catalogVersion: configuration.version,
                    updatedAt: configuration.updatedAt
                )
                context.insert(food)
                byKey[key] = food
            }
        }
    }

    private func sanitizedRows(_ rows: [SeedFood]) throws -> [String: SeedFood] {
        var incoming: [String: SeedFood] = [:]
        for row in rows {
            let key = Barcode.normalized(row.barcode)
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw CatalogStoreError.invalidFood("missing barcode") }
            guard !name.isEmpty else { throw CatalogStoreError.invalidFood("missing name") }
            guard row.barcode.utf8.count <= CatalogFieldLimit.barcodeBytes else {
                throw CatalogStoreError.invalidFood("barcode is too long")
            }
            guard name.utf8.count <= CatalogFieldLimit.nameBytes else {
                throw CatalogStoreError.invalidFood("name is too long")
            }
            guard row.kilojoulesPer100g.isFinite, row.kilojoulesPer100g >= 0 else {
                throw CatalogStoreError.invalidFood("invalid energy for \(name)")
            }
            if let serving = row.servingGrams, !serving.isFinite || serving <= 0 {
                throw CatalogStoreError.invalidFood("invalid serving for \(name)")
            }
            var sanitized = row
            sanitized.name = name
            sanitized.brand = try sanitizedBrand(row.brand)
            incoming[key] = sanitized
        }
        return incoming
    }

    private func sanitizedBrand(_ brand: String?) throws -> String? {
        guard let brand else { return nil }
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= CatalogFieldLimit.brandBytes else {
            throw CatalogStoreError.invalidFood("brand is too long")
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func apply(
        _ row: SeedFood,
        to food: CatalogFood,
        version: Int,
        updatedAt: Date
    ) {
        food.name = row.name
        food.brand = row.brand
        food.barcodeRaw = row.barcode
        food.kilojoulesPer100g = row.kilojoulesPer100g
        food.servingGrams = row.servingGrams
        food.catalogVersion = version
        food.updatedAt = updatedAt
    }

    private func catalogState(in context: ModelContext) -> CatalogState {
        if let state = try? context.fetch(FetchDescriptor<CatalogState>()).first {
            return state
        }
        let state = CatalogState()
        context.insert(state)
        return state
    }

    private func appSettings(in context: ModelContext) -> AppSettings {
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return settings
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }

    private static func metrics(for foods: [CatalogFood]) -> (rowCount: Int, estimatedBytes: Int) {
        let bytes = foods.reduce(into: 0) { total, food in
            total += estimatedBytes(
                barcode: food.barcodeRaw,
                name: food.name,
                brand: food.brand
            )
        }
        return (foods.count, bytes)
    }

    private static func metricsForSeedRows(_ foods: [SeedFood]) -> (rowCount: Int, estimatedBytes: Int) {
        let bytes = foods.reduce(into: 0) { total, food in
            total += estimatedBytes(barcode: food.barcode, name: food.name, brand: food.brand)
        }
        return (foods.count, bytes)
    }

    private static func estimatedBytes(barcode: String, name: String, brand: String?) -> Int {
        barcode.utf8.count + name.utf8.count + (brand?.utf8.count ?? 0) + 64
    }
}
