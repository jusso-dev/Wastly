import Foundation

public struct CatalogPack: Codable, Equatable, Sendable {
    public var version: Int
    public var etag: String?
    public var pack: Int
    public var totalPacks: Int
    public var foods: [SeedFood]

    public init(
        version: Int,
        etag: String? = nil,
        pack: Int = 1,
        totalPacks: Int = 1,
        foods: [SeedFood]
    ) {
        self.version = version
        self.etag = etag
        self.pack = pack
        self.totalPacks = totalPacks
        self.foods = foods
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case etag
        case pack
        case totalPacks
        case foods
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        pack = try container.decodeIfPresent(Int.self, forKey: .pack) ?? 1
        totalPacks = try container.decodeIfPresent(Int.self, forKey: .totalPacks) ?? 1
        foods = try container.decode([SeedFood].self, forKey: .foods)
    }
}

public enum CatalogSyncStatus: String, Equatable, Sendable {
    case updated
    case notModified
}

public struct CatalogSyncResult: Equatable, Sendable {
    public var status: CatalogSyncStatus
    public var downloadedRows: Int
    public var downloadedPacks: Int
    public var snapshot: CatalogStorageSnapshot

    public init(
        status: CatalogSyncStatus,
        downloadedRows: Int,
        downloadedPacks: Int,
        snapshot: CatalogStorageSnapshot
    ) {
        self.status = status
        self.downloadedRows = downloadedRows
        self.downloadedPacks = downloadedPacks
        self.snapshot = snapshot
    }
}

public enum CatalogSyncError: Error, Equatable, LocalizedError, Sendable {
    case disallowedURL
    case invalidResponse
    case invalidPack(expected: Int, received: Int)
    case inconsistentVersion
    case inconsistentPackCount
    case staleVersion(current: Int, received: Int)
    case tooManyPacks(limit: Int)
    case packTooLarge(limitBytes: Int)
    case downloadTooLarge(limitBytes: Int)
    case tooManyRows(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .disallowedURL:
            "The catalog endpoint must be an allowed HTTPS URL without credentials."
        case .invalidResponse:
            "The catalog service returned an invalid response."
        case let .invalidPack(expected, received):
            "The catalog returned pack \(received) while Wastly expected pack \(expected)."
        case .inconsistentVersion:
            "The catalog packs do not describe the same version."
        case .inconsistentPackCount:
            "The catalog packs do not agree on the total pack count."
        case let .staleVersion(current, received):
            "The catalog returned stale version \(received); this iPhone already has version \(current)."
        case let .tooManyPacks(limit):
            "The catalog exceeds Wastly’s \(limit)-pack download limit."
        case let .packTooLarge(limitBytes):
            "A catalog pack exceeds Wastly’s \(limitBytes.formatted())-byte download limit."
        case let .downloadTooLarge(limitBytes):
            "The catalog exceeds Wastly’s \(limitBytes.formatted())-byte download limit."
        case let .tooManyRows(limit):
            "The catalog exceeds Wastly’s \(limit.formatted())-food storage limit."
        }
    }
}

struct CatalogHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
    var etag: String?
}

protocol CatalogHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> CatalogHTTPResponse
}

private struct CatalogDownload {
    var foods: [SeedFood]
    var version: Int
    var etag: String?
    var packCount: Int
}

private enum CatalogDownloadOutcome {
    case notModified(etag: String?)
    case updated(CatalogDownload)
}

private struct PendingCatalogDownload {
    private(set) var foodsByBarcode: [String: SeedFood] = [:]
    private(set) var version: Int?
    private(set) var etag: String?
    private(set) var totalPacks = 1

    mutating func append(
        _ pack: CatalogPack,
        responseETag: String?,
        maximumRows: Int
    ) throws {
        version = pack.version
        totalPacks = pack.totalPacks
        if pack.pack == 1 {
            etag = responseETag ?? pack.etag
        }
        for food in pack.foods {
            foodsByBarcode[Barcode.normalized(food.barcode)] = food
        }
        guard foodsByBarcode.count <= maximumRows else {
            throw CatalogSyncError.tooManyRows(limit: maximumRows)
        }
    }

    func finished() throws -> CatalogDownload {
        guard let version else { throw CatalogSyncError.invalidResponse }
        return CatalogDownload(
            foods: Array(foodsByBarcode.values),
            version: version,
            etag: etag,
            packCount: totalPacks
        )
    }
}

private struct URLSessionCatalogHTTPClient: CatalogHTTPClient {
    var session: URLSession

    func data(for request: URLRequest) async throws -> CatalogHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CatalogSyncError.invalidResponse
        }
        return CatalogHTTPResponse(
            data: data,
            statusCode: http.statusCode,
            etag: http.value(forHTTPHeaderField: "ETag")
        )
    }
}

public actor CatalogSync {
    public static let defaultMaximumPackBytes = 8 * 1_024 * 1_024
    public static let defaultMaximumDownloadBytes = 64 * 1_024 * 1_024
    public static let defaultMaximumPacks = 100

    private let store: LocalFoodStore
    private let extraHosts: Set<String>
    private let client: any CatalogHTTPClient
    private let maximumPackBytes: Int
    private let maximumDownloadBytes: Int
    private let maximumPacks: Int
    private let maximumRows: Int

    public init(
        store: LocalFoodStore,
        extraHosts: Set<String> = [],
        session: URLSession = .shared,
        maximumPackBytes: Int = defaultMaximumPackBytes,
        maximumDownloadBytes: Int = defaultMaximumDownloadBytes,
        maximumPacks: Int = defaultMaximumPacks,
        maximumRows: Int = LocalFoodStore.defaultMaximumCatalogRows
    ) {
        self.store = store
        self.extraHosts = extraHosts
        self.client = URLSessionCatalogHTTPClient(session: session)
        self.maximumPackBytes = max(1, maximumPackBytes)
        self.maximumDownloadBytes = max(1, maximumDownloadBytes)
        self.maximumPacks = max(1, maximumPacks)
        self.maximumRows = max(1, maximumRows)
    }

    init(
        store: LocalFoodStore,
        extraHosts: Set<String> = [],
        client: any CatalogHTTPClient,
        maximumPackBytes: Int = defaultMaximumPackBytes,
        maximumDownloadBytes: Int = defaultMaximumDownloadBytes,
        maximumPacks: Int = defaultMaximumPacks,
        maximumRows: Int = LocalFoodStore.defaultMaximumCatalogRows
    ) {
        self.store = store
        self.extraHosts = extraHosts
        self.client = client
        self.maximumPackBytes = max(1, maximumPackBytes)
        self.maximumDownloadBytes = max(1, maximumDownloadBytes)
        self.maximumPacks = max(1, maximumPacks)
        self.maximumRows = max(1, maximumRows)
    }

    /// Downloads every incremental pack before one store commit. Failure or cancellation keeps the prior version.
    public func pull(from url: URL) async throws -> CatalogSyncResult {
        let current = await store.catalogSnapshot()
        do {
            guard PrivacyAllowlist.isAllowedCatalogURL(url, extraHosts: extraHosts) else {
                throw CatalogSyncError.disallowedURL
            }
            return try await result(for: download(from: url, current: current))
        } catch is CancellationError {
            await store.recordCatalogFailure("Catalog update cancelled. The previous version is still available.")
            throw CancellationError()
        } catch {
            await store.recordCatalogFailure(error.localizedDescription)
            throw error
        }
    }

    private func download(
        from url: URL,
        current: CatalogStorageSnapshot
    ) async throws -> CatalogDownloadOutcome {
        var pending = PendingCatalogDownload()
        var downloadedBytes = 0
        for requestedPack in 1...maximumPacks {
            try Task.checkCancellation()
            let request = try makeRequest(
                baseURL: url,
                currentVersion: current.version,
                pack: requestedPack,
                etag: requestedPack == 1 ? current.etag : nil
            )
            let response = try await client.data(for: request)
            try Task.checkCancellation()

            if requestedPack == 1, response.statusCode == 304 {
                return .notModified(etag: response.etag ?? current.etag)
            }
            downloadedBytes += response.data.count
            guard downloadedBytes <= maximumDownloadBytes else {
                throw CatalogSyncError.downloadTooLarge(limitBytes: maximumDownloadBytes)
            }
            let pack = try validatedPack(
                response,
                requestedPack: requestedPack,
                currentVersion: current.version,
                expectedVersion: pending.version,
                expectedPackCount: pending.version == nil ? nil : pending.totalPacks
            )
            try pending.append(pack, responseETag: response.etag, maximumRows: maximumRows)
            if requestedPack == pending.totalPacks {
                return .updated(try pending.finished())
            }
        }
        throw CatalogSyncError.invalidResponse
    }

    private func validatedPack(
        _ response: CatalogHTTPResponse,
        requestedPack: Int,
        currentVersion: Int,
        expectedVersion: Int?,
        expectedPackCount: Int?
    ) throws -> CatalogPack {
        guard (200..<300).contains(response.statusCode) else {
            throw CatalogSyncError.invalidResponse
        }
        guard response.data.count <= maximumPackBytes else {
            throw CatalogSyncError.packTooLarge(limitBytes: maximumPackBytes)
        }
        let decoded = try JSONDecoder().decode(CatalogPack.self, from: response.data)
        guard decoded.pack == requestedPack, decoded.pack <= decoded.totalPacks else {
            throw CatalogSyncError.invalidPack(expected: requestedPack, received: decoded.pack)
        }
        guard decoded.totalPacks >= 1, decoded.totalPacks <= maximumPacks else {
            throw CatalogSyncError.tooManyPacks(limit: maximumPacks)
        }
        guard decoded.version > currentVersion else {
            throw CatalogSyncError.staleVersion(current: currentVersion, received: decoded.version)
        }
        guard expectedVersion == nil || expectedVersion == decoded.version else {
            throw CatalogSyncError.inconsistentVersion
        }
        guard expectedPackCount == nil || expectedPackCount == decoded.totalPacks else {
            throw CatalogSyncError.inconsistentPackCount
        }
        return decoded
    }

    private func result(for outcome: CatalogDownloadOutcome) async throws -> CatalogSyncResult {
        switch outcome {
        case let .notModified(etag):
            let snapshot = await store.recordCatalogNotModified(etag: etag, checkedAt: .now)
            return CatalogSyncResult(
                status: .notModified,
                downloadedRows: 0,
                downloadedPacks: 0,
                snapshot: snapshot
            )
        case let .updated(download):
            try Task.checkCancellation()
            let snapshot = try await store.commitCatalog(
                download.foods,
                version: download.version,
                etag: download.etag,
                maximumRows: maximumRows
            )
            return CatalogSyncResult(
                status: .updated,
                downloadedRows: download.foods.count,
                downloadedPacks: download.packCount,
                snapshot: snapshot
            )
        }
    }

    private func makeRequest(
        baseURL: URL,
        currentVersion: Int,
        pack: Int,
        etag: String?
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "updatedSince", value: String(currentVersion)),
            URLQueryItem(name: "pack", value: String(pack))
        ]
        guard let requestURL = components?.url else {
            throw CatalogSyncError.disallowedURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(
            "Wastly/1.0 (https://github.com/jusso-dev/Wastly)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }
}
